#!/bin/bash
rm controls_wuup.txt
#find ./FHEM -type d \( ! -iname ".*" \) -print0 | while IFS= read -r -d '' f;
#  do
#   out="DIR $f"
#   echo ${out//.\//} >> controls_wuup.txt
#done
find ./FHEM -type f \( ! -iname ".*" \) -print0 | while IFS= read -r -d '' f;
  do
   out="UPD "$(stat -f "%Sm" -t "%Y-%m-%d_%T" $f)" "$(stat -f%z $f)" ${f}"
   echo ${out//.\//} >> controls_wuup.txt
done

# CHANGED file
echo "59_WUup.pm last change:" > CHANGED
echo $(date +"%Y-%m-%d") >> CHANGED
echo " - $(git log -1 --pretty=%B)" >> CHANGED
