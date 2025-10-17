package main

import (
    "crypto/rand"
    "encoding/hex"
    "fmt"
    "net/http"
    "os"
    "path/filepath"
)

const fileDir = "/opt/files/"

func main() {
    if err := os.MkdirAll(fileDir, os.ModePerm); err != nil {
        fmt.Printf("Error creating base directory: %v\n", err)
        return
    }

    http.HandleFunc("/", rootHandler)
    http.HandleFunc("/create", createHandler)

    fmt.Println("Сервер запущен на порту 8080")
    if err := http.ListenAndServe(":8080", nil); err != nil {
        fmt.Printf("Couldn't start server: %v\n", err)
    }
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method == http.MethodGet {
        fmt.Fprint(w, "nothing to do\n")
    } else {
        http.Error(w, "Method is not supported", http.StatusMethodNotAllowed)
    }
}

func createHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method is not supported", http.StatusMethodNotAllowed)
        return
    }

    fileName, err := generateRandomString(8)
    if err != nil {
        http.Error(w, "Failed to create file name", http.StatusInternalServerError)
        return
    }

    filePath := filepath.Join(fileDir, fileName)

    file, err := os.Create(filePath)
    if err != nil {
        http.Error(w, "Failed to create file", http.StatusInternalServerError)
        return
    }
    defer file.Close()

    fmt.Fprintf(w, "File %s has been created\n", fileName)
}

func generateRandomString(n int) (string, error) {
    bytes := make([]byte, n)
    if _, err := rand.Read(bytes); err != nil {
        return "", err
    }

    return hex.EncodeToString(bytes)[:n], nil
}
