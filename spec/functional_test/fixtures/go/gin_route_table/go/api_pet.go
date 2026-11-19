package openapi

import "github.com/gin-gonic/gin"

type PetAPI struct{}

func (api *PetAPI) AddPet(c *gin.Context)    { _ = c.ShouldBindJSON(&struct{ Name string }{}) }
func (api *PetAPI) DeletePet(c *gin.Context) { _ = c.GetHeader("api_key") }
func (api *PetAPI) FindPetsByStatus(c *gin.Context) {
	_ = c.Query("status")
}
