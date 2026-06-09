package com.example

class SearchEngine(private val footballTeamsApiHandler: FootballTeamsApiHandler) {
    fun getFilteredNames(nation: String): String {
        val teams = getTeams(nation)
        val filtered = filterByTitlesWonAndValuation(teams)
        return sortByValueThenName(filtered)
    }

    private fun getTeams(nation: String): String {
        return footballTeamsApiHandler.getAllPages(nation)
    }

    private fun filterByTitlesWonAndValuation(teams: String): String {
        return teams.filter { it.isLetter() }
    }

    private fun sortByValueThenName(teams: String): String {
        return teams.toList().sorted().joinToString("")
    }
}
