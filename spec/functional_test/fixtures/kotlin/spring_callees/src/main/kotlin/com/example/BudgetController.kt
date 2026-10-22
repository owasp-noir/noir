package com.example

import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/budget")
class BudgetController(private val budgetService: BudgetService) {
    @PostMapping("/priority")
    fun priority(): String {
        return budgetService.priority("city-1")
    }
}

class BudgetService(private val budgetRepository: BudgetRepository) {
    fun priority(id: String): String {
        budgetRepository.findAllUsers()
        budgetRepository.findAllRoles()
        budgetRepository.findAllSessions()
        budgetRepository.findAllTokens()
        budgetRepository.findAllDevices()
        budgetRepository.findAllAudits()
        budgetRepository.findAllEvents()
        budgetRepository.findAllNotifications()
        budgetRepository.findAllPreferences()
        budgetRepository.save(id)
        budgetRepository.deleteById(id)
        budgetRepository.findAllOrders()
        budgetRepository.findAllInvoices()
        budgetRepository.findAllPayments()
        budgetRepository.findAllShipments()
        budgetRepository.findAllCarts()
        budgetRepository.findAllCoupons()
        budgetRepository.findAllReviews()
        budgetRepository.findAllTickets()
        budgetRepository.findAllReports()
        budgetRepository.findAllAlerts()
        return id
    }
}

class BudgetRepository {
    fun findAllUsers(): List<String> = emptyList()

    fun findAllOrders(): List<String> = emptyList()

    fun findAllInvoices(): List<String> = emptyList()

    fun findAllPayments(): List<String> = emptyList()

    fun findAllShipments(): List<String> = emptyList()

    fun findAllCarts(): List<String> = emptyList()

    fun findAllCoupons(): List<String> = emptyList()

    fun findAllReviews(): List<String> = emptyList()

    fun findAllTickets(): List<String> = emptyList()

    fun findAllReports(): List<String> = emptyList()

    fun findAllAlerts(): List<String> = emptyList()

    fun findAllRoles(): List<String> = emptyList()

    fun findAllSessions(): List<String> = emptyList()

    fun findAllTokens(): List<String> = emptyList()

    fun findAllDevices(): List<String> = emptyList()

    fun findAllAudits(): List<String> = emptyList()

    fun findAllEvents(): List<String> = emptyList()

    fun findAllNotifications(): List<String> = emptyList()

    fun findAllPreferences(): List<String> = emptyList()

    fun save(id: String): String = id

    fun deleteById(id: String) {}
}
