# $Id: 59_WUup.pm 8 2017-02-22 17:45:35Z mahowi $
################################################################################
#    59_WUup.pm
#
#    Copyright: mahowi
#    e-mail: mahowi@gmx.net
#
#    Based on 55_weco.pm by betateilchen
#
#    This file is part of fhem.
#
#    Fhem is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 2 of the License, or
#    (at your option) any later version.
#
#    Fhem is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################

package main;

use strict;
use warnings;
#use experimental 'smartmatch';
use Time::HiRes qw(gettimeofday);
use HttpUtils;
use UConv;

my $version = "0.8";

# Declare functions
sub WUup_Initialize($);
sub WUup_Define($$$);
sub WUup_Undef($$);
sub WUup_Attr(@);
sub WUup_stateRequestTimer($);
sub WUup_send($);

################################################################################
#
# Main routines
#
################################################################################

sub WUup_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}   = "WUup_Define";
    $hash->{UndefFn} = "WUup_Undef";
    $hash->{AttrFn}  = "WUup_Attr";
    $hash->{AttrList} =
        "disable:1 "
      . "disabledForIntervals "
      . "interval "
      . "wuwinddir wuwindspeedmph wuwindgustmph wuwindgustdir wuwinddir_avg2m  "
      . "wuwinddir_avg2m wuwindgustmph_10m wuwindgustdir_10m wuhumidity "
      . "wusoilmoisture wudewptf wutempf wurainin wudailyrainin wubaromin "
      . "wusoiltempf wusolarradiation wuUV "
      . $readingFnAttributes;
    $hash->{VERSION} = $version;
}

sub WUup_Define($$$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "syntax: define <name> WUup <stationID> <password>"
      if ( int(@a) != 4 );

    my $name = $hash->{NAME};

    $hash->{VERSION}  = $version;
    $hash->{INTERVAL} = 300;

    $hash->{helper}{stationid}    = $a[2];
    $hash->{helper}{password}     = $a[3];
    $hash->{helper}{softwaretype} = 'fhem';
    $hash->{helper}{url} =
"https://weatherstation.wunderground.com/weatherstation/updateweatherstation.php";

    readingsSingleUpdate( $hash, "state", "defined", 1 );

    $attr{$name}{room} = "Weather" if ( !defined( $attr{$name}{room} ) );

    RemoveInternalTimer($hash);

    if ($init_done) {
        WUup_stateRequestTimer($hash);
    }
    else {
        InternalTimer( gettimeofday(), "WUup_stateRequestTimer", $hash, 0 );
    }

    Log3 $name, 3, "WUup ($name): defined";

    return undef;
}

sub WUup_Undef($$) {
    my ( $hash, $arg ) = @_;
    RemoveInternalTimer($hash);
    return undef;
}

sub WUup_Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "WUup ($name) - disabled";
        }

        elsif ( $cmd eq "del" ) {
            readingsSingleUpdate( $hash, "state", "active", 1 );
            Log3 $name, 3, "WUup ($name) - enabled";
        }
    }

    if ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            readingsSingleUpdate( $hash, "state", "unknown", 1 );
            Log3 $name, 3, "WUup ($name) - disabledForIntervals";
        }

        elsif ( $cmd eq "del" ) {
            readingsSingleUpdate( $hash, "state", "active", 1 );
            Log3 $name, 3, "WUup ($name) - enabled";
        }
    }

    if ( $attrName eq "interval" ) {
        if ( $cmd eq "set" ) {
            if ( $attrVal < 60 ) {
                Log3 $name, 3,
"WUup ($name) - interval too small, please use something >= 60 (sec), default is 300 (sec).";
                return
"interval too small, please use something >= 60 (sec), default is 300 (sec)";
            }
            else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "WUup ($name) - set interval to $attrVal";
            }
        }

        elsif ( $cmd eq "del" ) {
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "WUup ($name) - set interval to default";
        }
    }

    return undef;
}

sub WUup_stateRequestTimer($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( !IsDisabled($name) ) {
        readingsSingleUpdate( $hash, "state", "active", 1 )
          if (
            (
                   ReadingsVal( $name, "state", 0 ) eq "defined"
                or ReadingsVal( $name, "state", 0 ) eq "disabled"
                or ReadingsVal( $name, "state", 0 ) eq "Unknown"
            )
          );

        WUup_send($hash);

    }
    else {
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }

    InternalTimer( gettimeofday() + $hash->{INTERVAL},
        "WUup_stateRequestTimer", $hash, 1 );

    Log3 $name, 5,
      "Sub WUup_stateRequestTimer ($name) - Request Timer is called";
}

sub WUup_send($) {
    my ( $hash, $local ) = @_;
    my $name = $hash->{NAME};

    $local = 0 unless ( defined($local) );
    my $url = $hash->{helper}{url};
    $url .= "?ID=" . $hash->{helper}{stationid};
    $url .= "&PASSWORD=" . $hash->{helper}{password};
    my $datestring = strftime "%F+%T", gmtime;
    $datestring =~ s/:/%3A/g;
    $url .= "&dateutc=" . $datestring;

    my ( $data, $d, $r, $o );
    my $a = $attr{$name};
    while ( my ( $key, $value ) = each(%$a) ) {
        next if substr( $key, 0, 2 ) ne 'wu';
        $key = substr( $key, 2, length($key) - 2 );
        ( $d, $r, $o ) = split( ":", $value );
        if ( defined($r) ) {
            $o = ( defined($o) ) ? $o : 0;
            $value = ReadingsVal( $d, $r, 0 ) + $o;
        }
        if ( $key =~ /\w+f$/ ) {
            $value = UConv::c2f($value);
        }
        elsif ( $key =~ /\w+mph.*/ ) {
            $value = UConv::kph2mph($value);
        }
        elsif ( $key eq "baromin" ) {
            $value = UConv::hpa2inhg($value);
        }
        elsif ( $key =~ /.*rainin$/ ) {
            $value = UConv::mm2in($value);
        }
        $data .= "&$key=$value";
    }

    readingsBeginUpdate($hash);
    if ( defined($data) ) {
        readingsBulkUpdate( $hash, "data", $data );
        Log3 $name, 3, "WUup ($name) - data sent: $data";
        $url .= $data;
        $url .= "&softwaretype=" . $hash->{helper}{softwaretype};
        $url .= "&action=updateraw";
        Log3 $name, 4, "WUup ($name) - full URL: $url";
        my $response = GetFileFromURL($url);
        readingsBulkUpdate( $hash, "response", $response );
        Log3 $name, 3, "WUup ($name) - server response: $response";

    }
    else {
        CommandDeleteReading( undef, "$name data" );
        CommandDeleteReading( undef, "$name response" );
        Log3 $name, 3, "WUup ($name) - no data";
        readingsBulkUpdate( $hash, "state", "defined" );

    }
    readingsEndUpdate( $hash, 1 );

    return;
}

1;

################################################################################
#
# Documentation
#
################################################################################
#
# Changelog:
#
# 2017-01-23 initial release
# 2017-02-10 added german docu
# 2017-02-22 fixed bug when module can get reenabled after disabling
#            added disableForTimer
#            changed attribute WUInterval to interval
#            default interval 300
#
################################################################################

=pod
=item helper
=item summary sends weather data to Weather Underground
=item summary_DE sendet Wetterdaten zu Weather Underground
=begin html

<a name="WUup"></a>
<h3>WUup</h3>
<ul>

    <a name="WUupdefine"></a>
    <b>Define</b>
    <ul>

        <br/>
        <code>define &lt;name&gt; WUup &lt;stationId&gt; &lt;password&gt;</code>
        <br/><br/>
        This module provides connection to 
        <a href="https://www.wunderground.com">www.wunderground.com</a></br>
        to send data from your own weather station.<br/>

    </ul>
    <br/><br/>

    <a name="WUupset"></a>
    <b>Set-Commands</b><br/>
    <ul>
        <br/>
        - not implemented -<br/>
    </ul>
    <br/><br/>

    <a name="WUupget"></a>
    <b>Get-Commands</b><br/>
    <ul>
        <br/>
        - not implemented -<br/>
    </ul>
    <br/><br/>

    <a name="WUupattr"></a>
    <b>Attributes</b><br/><br/>
    <ul>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br/>
        <li><b>interval</b> - Interval (seconds) to send data to 
            www.wunderground.com. 
            Will be adjusted to 300 (which is the default) if set to a value lower than 60.</li>
        <li><b>disable</b> - disables the module</li>
        <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
        <li><b>wu....</b> - Attribute name corresponding to 
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">parameter name from api.</a> 
            Each of these attributes contains information about weather data to be sent 
            in format <code>sensorName:readingName[:offset]</code><br/>
            Example: <code>attr WUup wutempf outside:temperature</code> will 
            define the attribute wutempf and <br/>
            reading "temperature" from device "outside" will be sent to 
            network as parameter "tempf" (which indicates current temperature)
            <br/>
            Units get converted to angloamerican system automatically 
            (&deg;C -> &deg;F; km/h -> mph; mm -> in; hPa -> inHg)<br/>
            Optional Parameter "offset" will be added to the read value.
        </li>
    </ul>
    <br/><br/>

    <b>Readings/Events:</b>
    <br/><br/>
    <ul>
        <li><b>data</b> - data string transmitted to www.wunderground.com</li>
        <li><b>response</b> - response string received from server</li>
    </ul>
    <br/><br/>

    <b>Notes</b><br/><br/>
    <ul>
        <li>Find complete api description 
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">here</a></li>
        <li>Have fun!</li><br/>
    </ul>

</ul>

=end html
=begin html_DE

<a name="WUup"></a>
<h3>WUup</h3>
<ul>

    <a name="WUupdefine"></a>
    <b>Define</b>
    <ul>

        <br/>
        <code>define &lt;name&gt; WUup &lt;stationId&gt; &lt;password&gt;</code>
        <br/><br/>
        Dieses Modul stellt eine Verbindung zu <a href="https://www.wunderground.com">www.wunderground.com</a></br>
        her, um Daten einer eigenen Wetterstation zu versenden..<br/>

    </ul>
    <br/><br/>

    <a name="WUupset"></a>
    <b>Set-Befehle</b><br/>
    <ul>
        <br/>
        - keine -<br/>
    </ul>
    <br/><br/>

    <a name="WUupget"></a>
    <b>Get-Befehle</b><br/>
    <ul>
        <br/>
        - keine -<br/>
    </ul>
    <br/><br/>

    <a name="WUupattr"></a>
    <b>Attribute</b><br/><br/>
    <ul>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br/>
        <li><b>interval</b> - Sendeinterval in Sekunden. Wird auf 300 (Default-Wert)
        eingestellt, wenn der Wert kleiner als 60 ist.</li>
        <li><b>disable</b> - deaktiviert das Modul</li>
        <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
        <li><b>wu....</b> - Attributname entsprechend dem 
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">Parameternamen aus der API.</a><br />
        Jedes dieser Attribute enth&auml;lt Informationen &uuml;ber zu sendende Wetterdaten
        im Format <code>sensorName:readingName[:offset]</code>.<br/>
        Beispiel: <code>attr WUup wutempf outside:temperature</code> definiert
        das Attribut wutempf und sendet das Reading "temperature" vom Ger&auml;t "outside" als Parameter "tempf" 
        (welches die aktuelle Temperatur angibt).
        <br />
        Einheiten werden automatisch ins anglo-amerikanische System umgerechnet. 
        (&deg;C -> &deg;F; km/h -> mph; mm -> in; hPa -> inHg)<br/>
        Der optionale Parameter "offset" wird zum ausgelesenen Wert addiert.
        </li>
    </ul>
    <br/><br/>

    <b>Readings/Events:</b>
    <br/><br/>
    <ul>
        <li><b>data</b> - Daten, die zu www.wunderground.com gesendet werden</li>
        <li><b>response</b> - Antwort, die vom Server empfangen wird</li>
    </ul>
    <br/><br/>

    <b>Notizen</b><br/><br/>
    <ul>
        <li>Die komplette API-Beschreibung findet sich 
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">hier</a></li>
        <li>Viel Spa&szlig;!</li><br/>
    </ul>

</ul>

=end html_DE
=cut
