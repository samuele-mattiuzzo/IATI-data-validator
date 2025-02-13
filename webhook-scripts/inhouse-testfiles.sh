#!/bin/bash
# Process a single file from Google Storage
# Parameters:
# $1 - basename of the file (typically the md5sum of the file)

cd /home

PREFIX="Inhouse testfiles"
API=${API:-http://validator-api/api/v1}
BUCKET_SRC=${BUCKET_TEST_SRC:-dataworkbench-test}
BUCKET_FB=${BUCKET_TEST_FB:-dataworkbench-testfeedback}
BUCKET_JSON=${BUCKET_TEST_JSON:-dataworkbench-testjson}
BUCKET_SVRL=${BUCKET_TEST_SVRL:-dataworkbench-testsvrl}
VERSION=`grep 'variable name="schemaVersion"' lib/iati-rulesets/rules/iati.xslt | cut -f 2 -d \> | cut -f 1 -d \<`
filename=$1

# Try to get the file via our API

mkdir -p /workspace/input

HTTP_STATUS=$(curl -s "$API/iati-testfiles/$BUCKET_SRC/download/$filename" -o "/workspace/input/$filename" -w "%{http_code}")
echo "$PREFIX: retrieved $filename with status $HTTP_STATUS"

# If available:
if [[ $HTTP_STATUS == 200 ]]; then 
  basename=${filename%.*}
  
  # Make sure we process the file again by removing the target for ant
  rm -f /workspace/dest/$basename.feedback.xml
  # Run the XML check and the rules
  ant -f build-engine.xml -Dfilemask=$basename feedback
  
  # Store the result
  
  echo "$PREFIX: store feedback for $basename ($filename)"
  curl -sS -F "file=@/workspace/dest/$basename.feedback.xml;type=application/xml" "$API/iati-files/$BUCKET_FB/upload"
  
  FILEDATE=$(date -Iseconds -r /workspace/dest/$basename.feedback.xml)
  
  APIDATA="{\"feedback-updated\": \"$FILEDATE\", \"feedback-version\": \"$VERSION\", \"status\": \"Generating report (step 3 of 3)\"}"
  
  echo "$PREFIX: update iati-testdatasets for feedback on $basename ($filename)"
  curl -sS -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' \
  -d "$APIDATA" \
  "$API/iati-testdatasets/update?where=%7B%22fileid%22%3A%22$filename%22%7D"
  
  # Run the JSON conversion
  rm -f /workspace/json/$basename.json
  ant -f build-engine.xml -Dfilemask=$basename json
  
  # Store the result
  echo "$PREFIX: store json for $basename ($filename)"
  curl -sS -F "file=@/workspace/json/$basename.json;type=application/json" "$API/iati-files/$BUCKET_JSON/upload"
  
  FILEDATE=$(date -Iseconds -r /workspace/json/$basename.json)
  
  APIDATA="{\"json-updated\": \"$FILEDATE\", \"json-version\": \"$VERSION\", \"status\": \"Report generated\"}"
  
  echo "$PREFIX: update iati-testdatasets for json on $basename ($filename)"
  curl -sS -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' \
  -d "$APIDATA" \
  "$API/iati-testdatasets/update?where=%7B%22fileid%22%3A%22$filename%22%7D"
  
  # Run the SVRL conversion
  rm -f /workspace/svrl/$basename.svrl
  ant -f build-engine.xml -Dfilemask=$basename svrl
  
  # Store the result
  
  if xmllint --noout /workspace/svrl/$basename.svrl 2> "/dev/null"; then
    echo "$PREFIX: store svrl for $basename ($filename)"
    curl -sS -F "file=@/workspace/svrl/$basename.svrl;type=application/xml" "$API/iati-files/$BUCKET_SVRL/upload"
  
    FILEDATE=$(date -Iseconds -r /workspace/svrl/$basename.svrl)
  
    APIDATA="{\"svrl-updated\": \"$FILEDATE\", \"svrl-version\": \"$VERSION\"}"
  
    echo "$PREFIX: update iati-testdatasets for svrl on $basename ($filename)"
    curl -sS -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' \
    -d "$APIDATA" \
    "$API/iati-testdatasets/update?where=%7B%22fileid%22%3A%22$filename%22%7D"
  else
    echo "$PREFIX: svrl for $basename is not valid XML"
  fi

fi

# Remove the files from the local node if no second parameter given (allows to keep the artefacts for debugging)
if [[ -z $2 ]]; then
  find /workspace -name "${basename}*" -delete
fi
