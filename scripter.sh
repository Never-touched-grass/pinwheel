#!/bin/bash

declare -A variables
cdir=""

get_user_id() {
    sqlite3 users.db "SELECT id FROM users WHERE username = '$USERNAME';"
}

interpret() {
    local cmd="$1"
    local lines_name="$2"

    local user_id=$(get_user_id)
    if [ -z "$user_id" ]; then
        echo "Error: User ID not found."
        return 1
    fi

    if [ -z "$lines_name" ]; then
        if [[ "${cmd:0:6}" == "create" ]]; then
            cmd="${cmd:7}"
            read -r -a prs <<< "$cmd"
            local filename="${prs[0]}"

            if [[ -z "$filename" ]]; then
                echo "Usage: create <filename>"
                return
            fi

            local fullpath
            if [ "$cdir" != "" ]; then
                fullpath="$cdir/$filename"
            else
                fullpath="$filename"
            fi

            local exists=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id=$user_id AND path='$fullpath';")
            if [ "$exists" -gt 0 ]; then
                echo "File or folder '$filename' already exists."
                return
            fi

            if [ "$filename" == "-f" ]; then
                local foldername="${prs[1]}"
                if [[ -z "$foldername" ]]; then
                    echo "Usage: create -f <foldername>"
                    return
                fi

                if [ "$cdir" != "" ]; then
                    fullpath="$cdir/$foldername/"
                else
                    fullpath="$foldername/"
                fi

                sqlite3 users.db "INSERT INTO files (user_id, path, is_folder, content) VALUES ($user_id, '$fullpath', 1, '');"
                echo "Created empty folder '$foldername'."

            else
                sqlite3 users.db "INSERT INTO files (user_id, path, is_folder, content) VALUES ($user_id, '$fullpath', 0, '');"
                echo "Created empty file '$filename'."
            fi

        elif [[ "${cmd:0:4}" == "say " ]]; then
            local arg="${cmd:4}"
            if [[ "$arg" =~ ^\".*\"$ ]]; then
                arg="${arg:1:-1}"
                echo "$arg"
            else
                if [[ -v variables["$arg"] ]]; then
                    echo "${variables[$arg]}"
                else
                    echo "Variable '$arg' not defined."
                fi
            fi

        elif [[ "${cmd:0:3}" == "if " ]]; then
            echo "Error: Multi-line 'if' blocks should be handled outside interpret or by passing multiple lines."

        elif [[ "${cmd:0:6}" == "write " ]]; then
            local rest="${cmd:6}"
            read -r -a prs <<< "$rest"
            local filename="${prs[0]}"
            local content="${rest#"$filename"}"
            content="${content#"${content%%[![:space:]]*}"}"

            local filepath
            if [ "$cdir" != "" ]; then
                filepath="$cdir/$filename"
            else
                filepath="$filename"
            fi

            if [[ -z "$filename" ]]; then
                echo "Usage: write <filename> <content>"
                return
            fi

            local exists=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id=$user_id AND path='$filepath';")
            if [ "$exists" -eq 0 ]; then
                echo "File '$filename' does not exist."
                return
            fi

            sqlite3 users.db "UPDATE files SET content='$content' WHERE user_id=$user_id AND path='$filepath';"
            echo "Written to file '$filename'."

        elif [[ "${cmd:0:4}" == "get " ]]; then
            local filename="${cmd:4}"
            filename="${filename#"${filename%%[![:space:]]*}"}"

            local filepath
            if [ "$cdir" != "" ]; then
                filepath="$cdir/$filename"
            else
                filepath="$filename"
            fi

            local exists=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id=$user_id AND path='$filepath';")
            if [ "$exists" -eq 0 ]; then
                echo "File '$filename' does not exist in current directory."
                return
            fi

            local content=$(sqlite3 users.db "SELECT content FROM files WHERE user_id=$user_id AND path='$filepath';")
            echo "$content"

        elif [[ "${cmd:0:3}" == "cd " ]]; then
            local dir="${cmd:3}"

            if [ "$dir" == "home" ]; then
                cdir=""
            elif [ "$dir" == "-w" ]; then
                if [ "$cdir" != "" ]; then
                    echo "local-$USERNAME-home-$cdir"
                else
                    echo "local-$USERNAME-home"
                fi
            else
                local testdir
                if [ "$cdir" != "" ]; then
                    testdir="$cdir/$dir/"
                else
                    testdir="$dir/"
                fi

                local count=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id=$user_id AND path='$testdir' AND is_folder=1;")
                if [ "$count" -eq 0 ]; then
                    echo "Directory '$dir' does not exist."
                    return
                fi

                if [ "$cdir" != "" ]; then
                    cdir="$cdir/$dir"
                else
                    cdir="$dir"
                fi
            fi

        elif [[ "$cmd" == "list" ]]; then
            echo "Filesystem contents:"
            local prefix="$cdir"
            if [ -n "$prefix" ]; then
                prefix="$prefix/"
            fi
            sqlite3 users.db <<EOF | while IFS="|" read -r path is_folder; do
SELECT path, is_folder FROM files
WHERE user_id = $user_id AND path LIKE '$prefix%' AND
      instr(substr(path, length('$prefix') + 1), '/') = 0;
EOF
                if [ "$is_folder" -eq 1 ]; then
                    echo "[folder] $path"
                else
                    echo "[file]   $path"
                fi
            done

        elif [[ "${cmd:0:4}" == "set " ]]; then
            local assignment="${cmd:4}"
            if [[ "$assignment" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                local varname="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                variables["$varname"]="$value"
                echo "Variable '$varname' set to '$value'."
            else
                echo "Usage: set <varname> = <value>"
            fi

        else
            if [[ -n "$cmd" ]] && [[ "$cmd" != "exit" ]]; then
                read -r -a prs <<< "$cmd"
                echo "Unknown command: ${prs[0]}"
            fi
        fi
    else
        # Multi-line command, lines passed by name in lines_name array
        local -n lines_ref="$lines_name"
        for cmd in "${lines_ref[@]}"; do
            interpret "$cmd"
        done
    fi
}
