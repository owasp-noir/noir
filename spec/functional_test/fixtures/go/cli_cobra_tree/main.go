package main

import "github.com/spf13/cobra"

func main() {
	var root = &cobra.Command{Use: "shopctl"}

	var users = &cobra.Command{Use: "users"}
	var usersGet = &cobra.Command{Use: "get"}
	usersGet.Flags().String("user-id", "", "user id")
	users.AddCommand(usersGet)

	var orders = &cobra.Command{Use: "orders"}
	var ordersGet = &cobra.Command{Use: "get"}
	ordersGet.Flags().String("order-id", "", "order id")
	orders.AddCommand(ordersGet)

	root.AddCommand(users, orders)
	_ = root.Execute()
}
