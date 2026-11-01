#!/bin/bash
# Met le numero de version dans les deux manifests et compile le paquet public.
# Usage : .claude/skills/publier/build.sh 1.0.20
set -e
cd "$(dirname "$0")/../../.."

version="$1"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage : build.sh X.Y.Z" >&2
    exit 1
fi

sed -i '' -E "s/^( *version=\")[0-9.]+(\">)/\1$version\2/" manifest.xml manifest-public.xml
grep -q "version=\"$version\"" manifest.xml manifest-public.xml
python3 tools/make_buildinfo.py

export JAVA_HOME=~/Applications/jdk-21.0.12.1+1/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
# SDK 9.2.0 tant que la version 9.3.0 n'est pas adoptee pour les envois
sdk=$(ls -d ~/Library/Application\ Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-* | tail -1)
"$sdk/bin/monkeyc" -e -r -f public.jungle -y ~/Applications/developer_key -o bin/Windspot-public.iq 2>&1 | grep -v "^WARNING"
ls -la bin/Windspot-public.iq
