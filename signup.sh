#!/bin/bash
sqlite3 users.db "CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    password TEXT
);"

read -p "Enter username: " USERNAME

exists=$(sqlite3 users.db "SELECT COUNT(*) FROM users WHERE username = '$USERNAME';")

if [[ "$exists" =~ ^[0-9]+$ ]] && [ "$exists" -gt 0 ]; then
    read -sp "Enter password: " PASSWORD
    echo
    correct=$(sqlite3 users.db "SELECT password FROM users WHERE username = '$USERNAME';")
    if [ "$PASSWORD" != "$correct" ]; then
        echo "Incorrect password. Exiting."
        exit 1
    fi
    echo "Login successful!"
else
    echo "New user. Please register."
    read -sp "Create password: " PASSWORD
    echo
    sqlite3 users.db "INSERT INTO users (username, password) VALUES ('$USERNAME', '$PASSWORD');"
    echo "User registered!"
fi
