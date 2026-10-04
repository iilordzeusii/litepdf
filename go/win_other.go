//go:build !windows

package main

import "fmt"

func showWindow(url string) { fmt.Println("open", url); select {} }
