declare -A myfs
echo "Building source files..."
(cd ./expr && cargo build --release --quiet)
PY="./bin/python3/python.exe"
RS="./bin/rust/bin/rustc"
source ./scripter.sh

source ./signup.sh
cdir=""
echo "Welcome, $USERNAME"
echo "Type 'help' for more info."
cmd=""
varnames=()
vals=()
while [ "$cmd" != "exit" ]; do
    if [ "$cdir" == "" ]; then
    read -p "local-$USERNAME-home> " cmd
    else
        read -p "local-$USERNAME-home-$cdir> " cmd
    fi
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
            echo "${variables[${arg}]}"
        else
            echo "Variable '$arg' not defined."
        fi
    fi
    elif [[ "${cmd:0:3}" == "if " ]]; then
        inp=""
        iflines=()
        while true; do
            read -p "> " inp
            if [ "$inp" == "endif" ]; then
                break
            fi
            iflines+=("$inp")
        done
        cond="${cmd:3}"
        res=$(./expr/target/release/expr "$cond")

        if [ "$res" == "true" ]; then
            for line in "${iflines[@]}"; do
                interpret "$line"
            done
        else
            :
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
            elif [ "$dir" == "-w" ]; then
                if [ "$cdir" != "" ]; then
                    echo "local-$USERNAME-home-$cdir"
                else
                    echo "local-$USERNAME-home"
                fi
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
    elif [[ "${cmd:0:4}" == "help" ]]; then
        echo "Copyright 2025 Pinwheel Studios."
        echo "Commands:"
        echo "say: Prints a string or variable to the screen."
        echo "create: creates a new file. Use the -f flag after create to create a folder. i.e. create -f MyFolder or create MyFile"
        echo "write: writes content to a file. i.e. write MyFile content"
        echo "get: gets the content of a file and prints it to the screen. i.e. get MyFile"
        echo "exit: exit the shell."
        echo "set: sets a variable. i.e. set MyVariable = someValue <- Note that strings are NOT encased in quotes."
        echo "list: lists all files and folders."
        echo "cd: change the current working directory. If you created a folder, do: cd MyFolder. To print the current working directory, type cd -w."
        echo "if: checks a condition and runs lines entered based on the evaluation of said condition. For example, if 5 < 10 will run, but if 5 > 10 won't. type 'endif' to stop writing inside the if statement and evaluate the code."
    else
        if [ "$cmd" != "" ] && [ "$cmd" != "exit" ]; then
            read -r -a prs <<< "$cmd"
            echo "Unknown command: ${prs[0]}"
        fi
    fi
done