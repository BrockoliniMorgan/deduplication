#!/usr/bin/env bash

declare -A file_hashes
HASHING_ALGO=sha256sum
BACKUP_HASHING_ALGO=md5sum

read -r -d '' USAGE_MSG <<EOF
USAGE: deduplication.bash [options]
OPTIONS:
        -h      Prints this message
        -f      Performs the deduplication on the supplied folder, defaults to pwd
        -a      Performs hashing using the supplied algorithm, defaults to sha256sum
        -b      Performs backup hashing using the supplied algorithm, defaults to md5sum
EOF

resolve_relative_path() (
        # If the path is a directory, we just need to 'cd' into it and print the new path.
        if [ -d "$1" ]; then
                cd "$1" || return 1
                pwd
        # If the path points to anything else, like a file or FIFO
        elif [ -e "$1" ]; then
                # Strip '/file' from '/dir/file'
                # We only change the directory if the name doesn't match for the cases where
                # we were passed something like 'file' without './'
                if [ ! "${1%/*}" = "$1" ]; then
                        cd "${1%/*}" || return 1
                fi
                # Strip all leading slashes upto the filename
                echo "$(pwd)/${1##*/}"
        else
                return 1 # Failure, neither file nor directory exists.
        fi
)

usage() {
        echo "$USAGE_MSG"
}

check_if_exists() {
        local new_hash="$1"
        local new_file_name="$2"
        local file_hash file

        for file in "${!file_hashes[@]}"; do
                file_hash=${file_hashes[$file]}
                if [[ "$file_hash" == "$new_hash" ]]; then
                        new_backup_hash=$($BACKUP_HASHING_ALGO "$new_file_name")
                        new_backup_hash=${new_backup_hash%% *}
                        backup_hash=$($BACKUP_HASHING_ALGO -b "$file")
                        backup_hash=${backup_hash%% *}
                        if [[ "$new_backup_hash" == "$backup_hash" ]]; then
                                echo "$new_file_name is the same as $file"
                                return 1
                        fi
                fi
        done

        echo "$new_file_name is a new file"
        file_hashes[$new_file_name]="$new_hash"
}

deduplicate() {
        local DIRECTORY thing
        DIRECTORY="$1"
        for thing in "$DIRECTORY"/*; do
                if [[ -f $thing ]]; then
                        hash=$($HASHING_ALGO -b "$thing")
                        # Remove the filename from the output of sha256sum
                        hash=${hash%% *}
                        check_if_exists "$hash" "$thing"
                else
                        echo "$thing is a directory"
                        deduplicate "$thing"
                fi
        done
}

main() {
        local OPTIND OPTARG opt DIRECTORY
        DIRECTORY="$PWD"

        while getopts "hf:a:b:" opt; do
                case "$opt" in
                h)
                        usage
                        exit 0
                        ;;
                f)
                        DIRECTORY="$(resolve_relative_path "$OPTARG")"
                        ;;
                a)
                        HASHING_ALGO="$OPTARG"
                        ;;
                b)
                        BACKUP_HASHING_ALGO="$OPTARG"
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
