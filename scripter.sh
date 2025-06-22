interpret() {
    local cmd="$1"

    if [[ "${cmd:0:6}" == "create" ]]; then
        cmd="${cmd:7}"
        read -r -a prs <<< "$cmd"
        filename="${prs[0]}"

        if [[ -z "$filename" ]]; then
            echo "Usage: create <filename>"
        elif [[ -n "${myfs[$filename]+_}" ]]; then
            echo "File '$filename' already exists."
        else
            if [ "$filename" == "-f" ]; then
                foldername="${prs[1]}"
                myfs["$foldername/"]=""
                echo "Created empty folder '$foldername'."
            else
                if [ "$cdir" != "" ]; then
                    fullpath="$cdir/$filename"
                    myfs["$fullpath"]=""
                    echo "Created empty file '$filename' in folder '$cdir'."
                else
                    myfs["$filename"]=""
                    echo "Created empty file '$filename'."
                fi
            fi
        fi

    elif [[ "${cmd:0:4}" == "say " ]]; then
        arg="${cmd:4}"
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

    elif [[ "${cmd:0:6}" == "write " ]]; then
        rest="${cmd:6}"
        read -r -a prs <<< "$rest"
        filename="${prs[0]}"
        content="${rest#"$filename"}"
        content="${content#"${content%%[![:space:]]*}"}"
        if [ "$cdir" != "" ]; then
            filepath="$cdir/$filename"
        else
            filepath="$filename"
        fi
        if [[ -z "$filename" ]]; then
            echo "Usage: write <filename> <content>"
        elif [[ -z "${myfs[$filepath]+_}" ]]; then
            echo "File '$filename' does not exist."
        else
            myfs["$filepath"]="$content"
            echo "Written to file '$filename'."
        fi

    elif [[ "${cmd:0:4}" == "get " ]]; then
        filename="${cmd:4}"
        filename="${filename#"${filename%%[![:space:]]*}"}"
        if [ "$cdir" != "" ]; then
            filepath="$cdir/$filename"
        else
            filepath="$filename"
        fi
        if [[ -z "${myfs[$filepath]+_}" ]]; then
            echo "File '$filename' does not exist in current directory."
        else
            echo "${myfs[$filepath]}"
        fi

    elif [[ "${cmd:0:3}" == "cd " ]]; then
        dir="${cmd:3}"
        if [[ -z "${myfs[$dir/]+_}" ]]; then
            if [ "$dir" == "home" ]; then
                cdir=""
            else
                echo "Directory '$dir' does not exist."
            fi
        else
            cdir="$dir"
        fi

    elif [[ "$cmd" == "list" ]]; then
        echo "Filesystem contents:"
        for k in "${!myfs[@]}"; do
            if [[ "$k" == */ ]]; then
                echo "[folder] $k"
            else
                echo "[file]   $k"
            fi
        done

    elif [[ "${cmd:0:4}" == "set " ]]; then
        assignment="${cmd:4}"
        if [[ "$assignment" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            varname="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
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
}
