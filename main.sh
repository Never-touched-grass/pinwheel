#!/bin/bash

echo "Building source files..."
(cd ./expr && cargo build --release --quiet)

if ! command -v sqlite3 &> /dev/null; then
    echo "[!] sqlite3 is not installed."

    if [ -f /etc/debian_version ]; then
        read -p "Install sqlite3 using apt? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            sudo apt update && sudo apt install -y sqlite3
        else
            echo "sqlite3 is required to continue. Exiting."
            exit 1
        fi
    else
        echo "[!] This script only supports auto-install on Debian/Ubuntu. Please install sqlite3 manually."
        exit 1
    fi
fi

PY="./bin/python3/python.exe"
RS="./bin/rust/bin/rustc"

source ./scripter.sh
source ./signup.sh

sqlite3 users.db "
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    path TEXT NOT NULL,
    is_folder INTEGER NOT NULL,
    content TEXT,
    UNIQUE(user_id, path),
    FOREIGN KEY(user_id) REFERENCES users(id)
);
"

get_user_id() {
    sqlite3 users.db "SELECT id FROM users WHERE username = '$USERNAME';"
}

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

    user_id=$(get_user_id)
    if [ -z "$user_id" ]; then
        echo "Error: User ID not found."
        exit 1
    fi

    if [[ "${cmd:0:6}" == "create" ]]; then
        cmd="${cmd:7}"
        read -r -a prs <<< "$cmd"
        filename="${prs[0]}"
        if [[ -z "$filename" ]]; then
            echo "Usage: create <filename>"
            continue
        fi

        if [ "$cdir" != "" ]; then
            fullpath="$cdir/$filename"
        else
            fullpath="$filename"
        fi

        exists=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id = $user_id AND path = '$fullpath';")
        if [ "$exists" -gt 0 ]; then
            echo "File or folder '$filename' already exists."
            continue
        fi

        if [ "$filename" == "-f" ]; then
            foldername="${prs[1]}"
            if [[ -z "$foldername" ]]; then
                echo "Usage: create -f <foldername>"
                continue
            fi

            if [ "$cdir" != "" ]; then
                fullpath="$cdir/$foldername/"
            else
                fullpath="$foldername/"
            fi

            sqlite3 users.db "INSERT INTO files (user_id, path, is_folder, content) VALUES ($user_id, '$fullpath', 1, '');"
            echo "Created empty folder '$foldername'."

        elif [[ "$filename" == *.pwl ]]; then
            filename="${filename%.pwl}"
            if [ "$cdir" != "" ]; then
                fullpath="$cdir/$filename"
            else
                fullpath="$filename"
            fi
            echo "Enter lines for executable file '$filename'. Type 'done' when finished:"
            lines=()
            lc=1
            while true; do
                read -p "$lc. " inp
                [[ "$inp" == "done" ]] && break
                lines+=("$inp")
                ((lc++))
            done
            content=$(printf "%s\n" "${lines[@]}")
            sqlite3 users.db "INSERT INTO files (user_id, path, is_folder, content) VALUES ($user_id, '$fullpath', 0, '$content');"
            echo "Created executable file '$filename'."

        else
            sqlite3 users.db "INSERT INTO files (user_id, path, is_folder, content) VALUES ($user_id, '$fullpath', 0, '');"
            echo "Created empty file '$filename'."
        fi

    elif [[ "${cmd:0:4}" == "say " ]]; then
        arg="${cmd:4}"
        if [[ "$arg" =~ ^\".*\"$ ]]; then
            arg="${arg:1:-1}"
            echo "$arg"
        else
            res=$(./expr/target/release/expr "check" "$arg")
            if [ "$res" == "true" ]; then
                res=$(./expr/target/release/expr "eval" "$arg")
                echo "$res"
            else
                found=false
                for ((i=0; i<${#varnames[@]}; i++)); do
                    if [ "${varnames[$i]}" == "$arg" ]; then
                        echo "${vals[$i]}"
                        found=true
                        break
                    fi
                done
                if [ "$found" = false ]; then
                    echo "Variable '$arg' not defined."
                fi
            fi
        fi

    elif [[ "${cmd:0:3}" == "if " ]]; then
        inp=""
        iflines=()
        while true; do
            read -p "> " inp
            [[ "$inp" == "endif" ]] && break
            iflines+=("$inp")
        done

        cond="${cmd:3}"
        for ((i=0; i<${#varnames[@]}; i++)); do
            var="${varnames[$i]}"
            val="${vals[$i]}"
            cond=$(echo "$cond" | sed -E "s/(^|[^a-zA-Z0-9_])$var([^a-zA-Z0-9_]|$)/\1$val\2/g")
        done

        res=$(./expr/target/release/expr "eval" "$cond")
        if [ "$res" == "true" ]; then
            for line in "${iflines[@]}"; do
                interpret "$line"
            done
        fi

    elif [[ "${cmd:0:2}" == "./" ]]; then
        filename="${cmd:2}"
        if [ "$cdir" != "" ]; then
            fullpath="$cdir/$filename"
        else
            fullpath="$filename"
        fi

        exists=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id = $user_id AND path = '$fullpath' AND is_folder = 0;")
        if [ "$exists" -eq 0 ]; then
            echo "File '$filename' not found."
        else
            content=$(sqlite3 users.db "SELECT content FROM files WHERE user_id = $user_id AND path = '$fullpath';")
            IFS=$'\n' read -rd '' -a lines <<< "$content"
            for line in "${lines[@]}"; do
                interpret "$line"
            done
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

        exists=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id = $user_id AND path = '$filepath';")
        if [[ -z "$filename" ]]; then
            echo "Usage: write <filename> <content>"
        elif [ "$exists" -eq 0 ]; then
            echo "File '$filename' does not exist."
        else
            sqlite3 users.db "UPDATE files SET content = '$content' WHERE user_id = $user_id AND path = '$filepath';"
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

        exists=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id = $user_id AND path = '$filepath';")
        if [ "$exists" -eq 0 ]; then
            echo "File '$filename' does not exist in current directory."
        else
            content=$(sqlite3 users.db "SELECT content FROM files WHERE user_id = $user_id AND path = '$filepath';")
            echo "$content"
        fi

    elif [[ "${cmd:0:3}" == "cd " ]]; then
        dir="${cmd:3}"
        if [ "$dir" == "home" ]; then
            cdir=""
        elif [ "$dir" == "-w" ]; then
            if [ "$cdir" != "" ]; then
                echo "local-$USERNAME-home-$cdir"
            else
                echo "local-$USERNAME-home"
            fi
        else
            testdir="$dir/"
            if [ "$cdir" != "" ]; then
                testdir="$cdir/$testdir"
            fi
            count=$(sqlite3 users.db "SELECT COUNT(*) FROM files WHERE user_id = $user_id AND path = '$testdir' AND is_folder = 1;")
            if [ "$count" -eq 0 ]; then
                echo "Directory '$dir' does not exist."
            else
                if [ "$cdir" != "" ]; then
                    cdir="$cdir/$dir"
                else
                    cdir="$dir"
                fi
            fi
        fi

    elif [[ "$cmd" == "list" ]]; then
        echo "Filesystem contents:"
        prefix="$cdir"
        [ -n "$prefix" ] && prefix="$prefix/"
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
        assignment="${cmd:4}"
        if [[ "$assignment" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            varname="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            found=false
            for ((i=0; i<${#varnames[@]}; i++)); do
                if [ "${varnames[$i]}" == "$varname" ]; then
                    vals[$i]="$value"
                    found=true
                    break
                fi
            done
            if [ "$found" == false ]; then
                varnames+=("$varname")
                vals+=("$value")
            fi
            echo "Variable '$varname' set to '$value'."
        else
            echo "Usage: set <varname> = <value>"
        fi

    elif [[ "${cmd:0:4}" == "help" ]]; then
        echo "Commands:"
        echo "say: Prints a string or variable to the screen."
        echo "create: creates a new file. Use the -f flag after create to create a folder. i.e. create -f MyFolder or create MyFile"
        echo "write: writes content to a file. i.e. write MyFile content"
        echo "get: gets the content of a file and prints it to the screen. i.e. get MyFile"
        echo "exit: exit the shell."
        echo "set: sets a variable. i.e. set MyVariable = someValue"
        echo "list: lists all files and folders."
        echo "cd: change directory. Use cd MyFolder. To print working dir: cd -w"
        echo "if: use 'if <condition>' then write lines until 'endif'."

    elif [ "$cmd" == "erase" ]; then
        read -sp "[system] Password for $USERNAME: " pass
        echo
        if [ "$pass" != "$PASSWORD" ]; then
            echo "Invalid password entered."
        else
            read -p "[!] WARNING: This will remove all users and data. Type 'yes' to confirm: " confirm
            if [ "$confirm" == "yes" ]; then
                sqlite3 users.db "DELETE FROM files;"
                sqlite3 users.db "DELETE FROM users;"
                echo "All users and files erased."
            else
                echo "Erase cancelled."
            fi
        fi

    else
        if [ "$cmd" != "" ] && [ "$cmd" != "exit" ]; then
            read -r -a prs <<< "$cmd"
            echo "Unknown command: ${prs[0]}"
        fi
    fi
done
