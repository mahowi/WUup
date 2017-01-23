#!/bin/bash
CONTROL=controls_wuup.txt
DIRS="./FHEM"

rm $CONTROL

find $DIRS -type f \( ! -iname ".*" \) -print0 | while IFS= read -r -d '' f;
  do
    out="UPD `stat --format "%z %s" $f | sed -e "s#\([0-9-]*\)\ \([0-9:]*\)\.[0-9]*\ [+0-9]*#\1_\2#"` $f"
    echo ${out//.\//} >> $CONTROL
done

# CHANGED file
echo "59_WUup.pm last change:" > CHANGED
echo $(date +"%Y-%m-%d") >> CHANGED
echo " - $(git log -1 --pretty=%B)" >> CHANGED
