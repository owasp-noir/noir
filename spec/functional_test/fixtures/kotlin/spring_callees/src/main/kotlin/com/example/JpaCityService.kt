package com.example

class JpaCityService(private val cityRepository: CityRepository) : CityService {
    override fun updateCity(id: String): String {
        val current = cityRepository.findById(id)
        return cityRepository.save(current)
    }
}
