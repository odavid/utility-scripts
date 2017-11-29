#!/bin/bash
set -e

program=$0

usage(){
    cat << EOF
Usage: $program [options...] --s3-url <s3-url> --file-name <destination-file>
Options:
-u, --s3-url <s3-url>                               - S3 file to be watched and fetched
-f, --file-name <destination-file>                  - Absolute destination filename
-d,--cache-dir <cache-dir>                          - Cached directory (Default: /tmp/.s3.cache)
--polling-interval <polling-interval-in-seconds>]   - Polling interval in seconds (Default 30)
--command <command-to-execute-on-change>            - Command to be executed if the file was changed
--first-time-execute                                - Should execute command on first time (Default: false)
--skip-watch                                        - Skip watch the file, only fetch it once (Default: false)
--debug                                             - Log debug (Default: false)
    
EOF
    exit 1
}

log(){
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

debug(){
    [[ "$DEBUG" == "YES" ]] && log "$1"
}


fetch_config(){
    debug "Fetching ${S3_URL} to ${CACHE_DIR}"
    aws --region=${S3_BUCKET_LOCATION} s3 cp ${S3_URL} ${CACHE_DIR}/${FILE_BASENAME} --quiet
    debug "Calulating checksum of ${CACHE_DIR}/${FILE_BASENAME}"
    MD5_CHECKSUM=$(md5 -q ${CACHE_DIR}/${FILE_BASENAME})
    debug "MD5_CHECKSUM = $MD5_CHECKSUM"
    if [ -f ${CACHE_DIR}/${FILE_BASENAME}.md5 ]; then
        ORIG_MD5_CHECKSUM=$(cat ${CACHE_DIR}/${FILE_BASENAME}.md5)
    else
        ORIG_MD5_CHECKSUM=''
    fi
    debug "ORIG_MD5_CHECKSUM = $ORIG_MD5_CHECKSUM"
    md5 -q ${CACHE_DIR}/${FILE_BASENAME} > ${CACHE_DIR}/${FILE_BASENAME}.md5
    if [ "$ORIG_MD5_CHECKSUM" != "$MD5_CHECKSUM" ]; then
        cp ${CACHE_DIR}/${FILE_BASENAME} ${FILENAME}
        return 30
    fi
    return 0
}

exec_command(){
    if [ -n "$COMMAND" ]; then
        log "Running $COMMAND."
        eval "$COMMAND"
        log "Running $COMMAND. Done..."
    fi
}

parseArgs(){
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case "$key" in
        -u|--s3-url)
        S3_URL="$2"
        shift # past argument
        shift # past value
        ;;
        
        -d|--cache-dir)
        CACHE_DIR="$2"
        shift # past argument
        shift # past value
        ;;
        
        -p|--polling-interval)
        POLLING_INTERVAL="$2"
        shift # past argument
        shift # past value
        ;;
        
        -f|--filename)
        FILENAME="$2"
        shift # past argument
        shift # past value
        ;;

        -c|--command)
        COMMAND="$2"
        shift # past argument
        shift # past value
        ;;

        --skip-watch)
        SKIP_WATCH=YES
        shift # past argument
        ;;

        --first-time-execute)
        FIRST_TIME_EXECUTE=YES
        shift # past argument
        ;;

        -h|--help)
        HELP=YES
        shift # past argument
        ;;
        
        --debug)
        DEBUG=YES
        shift # past argument
        ;;
        *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
    done
    set -- "${POSITIONAL[@]}" # restore positional parameters

    if [ -n "$HELP" ]; then
        usage
    fi

    if [[ -z "$S3_URL" ]]; then 
        (>&2 echo "Error: --s3-url must be provided")
        usage
    fi
    if [[ -z "$FILENAME" ]]; then 
        (>&2 echo "Error: --filename must be provided")
        usage
    fi

    POLLING_INTERVAL=${POLLING_INTERVAL:-30}
    CACHE_DIR=${CACHE_DIR:-/tmp/.s3.cache}
    S3_BUCKET=$(echo $S3_URL | sed 's/s3:\/\///g' | cut -d'/' -f 1)
    S3_BUCKET_LOCATION="$(aws s3api get-bucket-location --bucket ${S3_BUCKET} --output text)"
    [[ "$S3_BUCKET_LOCATION" == 'None' ]] && S3_BUCKET_LOCATION='us-east-1'
    FILE_BASENAME=$(basename $FILENAME)
}

parseArgs "$@"
log "$program started"
log "S3_URL = $S3_URL"
log "CACHE_DIR = $CACHE_DIR"
log "POLLING_INTERVAL = $POLLING_INTERVAL"
log "FILENAME = $FILENAME"
log "COMMAND = $COMMAND"
log "SKIP_WATCH = $SKIP_WATCH"
log "DEBUG = $DEBUG"

mkdir -p $CACHE_DIR

log "Fetching $FILENAME for the first time..."
fetch_config && FETCH_RES=$? || FETCH_RES=$?

if [ "$FIRST_TIME_EXECUTE" == "YES" ]; then
    log "FIRST_TIME_EXECUTE = YES, executing command"
    exec_command
fi

if [ "$SKIP_WATCH" == "YES" ]; then
    log "SKIP_WATCH = YES, Going out..."
    exit 0
fi

log "Entering watch loop"
while true; do
    sleep $POLLING_INTERVAL
    fetch_config && RES=$? || RES=$?
    if [ "$RES" == 30 ]; then
        log "Checksum was changed, executing command"
        exec_command
    fi
done