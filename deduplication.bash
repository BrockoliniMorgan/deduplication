#!/usr/bin/env bash

declare -A file_hashes
HASHING_ALGO=sha256sum
BACKUP_HASHING_ALGO=md5sum

read -r -d '' USAGE_MSG <<EOF
USAGE: deduplication.bash [options]
OPTIONS:
        -h              Prints this message
        -f FOLDER       Performs the deduplication on the supplied folder, defaults to pwd
        -a ALGORITHM    Performs hashing using the supplied algorithm, defaults to sha256sum
        -b ALGORITHM    Performs backup hashing using the supplied algorithm, defaults to md5sum
        -q              Quiet mode - Do not say when a new file or a directory is found
EOF

usage() {
        echo "$USAGE_MSG"
}

resolve_relative_path() (
        # If the path is a directory, we just need to 'cd' into it and print the new path.
        if [[ -d "$1" ]]; then
                cd "$1" || return 1
                pwd
        # If the path points to anything else, like a file or FIFO
        elif [[ -e "$1" ]]; then
                # Strip '/file' from '/dir/file'
                # We only change the directory if the name doesn't match for the cases where
                # we were passed something like 'file' without './'
                if [[ ! "${1%/*}" = "$1" ]]; then
                        cd "${1%/*}" || return 1
                fi
                # Strip all leading slashes upto the filename
                echo "$(pwd)/${1##*/}"
        else
                return 1 # Failure, neither file nor directory exists.
        fi
)

check_if_exists() {
        local check_file_hash check_file new_file_hash new_backup_hash check_backup_hash
        local new_file_name="$1"
        new_file_hash=$($HASHING_ALGO -b "$new_file_name")
        # Remove the filename from the output of the hashing algo
        new_file_hash=${new_file_hash%% *}

        for check_file in "${!file_hashes[@]}"; do
                check_file_hash=${file_hashes[$check_file]}
                if [[ "$check_file_hash" == "$new_file_hash" ]]; then
                        new_backup_hash=$($BACKUP_HASHING_ALGO "$new_file_name")
                        # Remove the filename from the output of the hashing algo
                        new_backup_hash=${new_backup_hash%% *}
                        check_backup_hash=$($BACKUP_HASHING_ALGO -b "$check_file")
                        check_backup_hash=${check_backup_hash%% *}
                        if [[ "$new_backup_hash" == "$check_backup_hash" ]]; then
                                echo "$new_file_name is the same as $check_file"
                                return 1
                        fi
                fi
        done

        if [[ -z ${QUIET+x} ]]; then
                echo "$new_file_name is a new file"
        fi
        file_hashes[$new_file_name]="$new_file_hash"
}

deduplicate() {
        local DIRECTORY thing
        DIRECTORY="$1"
        for thing in "$DIRECTORY"/*; do
                if [[ -f $thing ]]; then
                        check_if_exists "$thing"
                else
                        if [[ -z ${QUIET+x} ]]; then
                                echo "$thing is a directory"
                        fi
                        deduplicate "$thing"
                fi
        done
}

main() {
        local OPTIND OPTARG opt DIRECTORY
        DIRECTORY="$PWD"

        while getopts "qhf:a:b:" opt; do
                case "$opt" in
                h)
                        usage
                        exit 0
                        ;;
                f)
                        DIRECTORY="$(resolve_relative_path "$OPTARG")"
                        exit_code="$?"
                        if [[ "$exit_code" -ne 0 ]]; then
                                echo "$OPTARG is not a real folder"
                                usage >&2
                                exit 1
                        fi
                        ;;
                a)
                        HASHING_ALGO="$OPTARG"
                        ;;
                b)
                        BACKUP_HASHING_ALGO="$OPTARG"
                        ;;
                q)
                        QUIET=1
                        ;;
                *)
                        usage >&2
                        exit 1
                        ;;
                esac
        done

        deduplicate "$DIRECTORY"
        return 0
}

main "$@"
