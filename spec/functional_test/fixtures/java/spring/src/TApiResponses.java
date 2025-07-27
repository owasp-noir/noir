package com.test;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/multi/annotation")
public class TApiResponses {

    @GetMapping
    @ApiResponses(value = {
    @ApiResponse(responseCode = "200", description = "Success"),
    @ApiResponse(responseCode = "400", description = "Invalid parameters",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class))),
    @ApiResponse(responseCode = "401", description = "Authentication error",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class))),
    @ApiResponse(responseCode = "404", description = "Not found",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class))),
    @ApiResponse(responseCode = "500", description = "Internal server error",
       content = @Content(schema = @Schema(implementation = ErrorResponse.class)))})
    public String greet(HttpServletRequest request) {
        String name = request.getParameter("name");
        if (name == null || name.isEmpty()) {
            name = "World";
        }

        String header = request.getHeader("header");
        if (header == null || header.isEmpty()) {
            header = "!";
        }
        return "Hello, " + name + header;
    }
}