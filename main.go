package main

import (
	"fmt"
	"github.com/NebulousLabs/fastrand"
	"os"
	"strings"
)

func main() {
	fmt.Printf("current mode: %v, random int: %v\n", os.Getenv("MODE"), fastrand.Intn(10))
	strs := [3]string{"https://github.com", "idealism-xxm", "debugging-go-in-docker-with-goland-and-vscode"}
	url := strings.Join(strs[:], "/")
	fmt.Println(url)
}
