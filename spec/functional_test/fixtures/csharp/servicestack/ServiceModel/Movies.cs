using ServiceStack;

namespace ServiceStackDemo.ServiceModel
{
    // Two independent [Route] attributes on the same DTO, each with its own
    // verb set. This is the shape ServiceStack's own examples use, and it's
    // important the verbs on one attribute never leak onto the other: /movies
    // only answers the write verbs below, /movies/{Id} answers every verb
    // (the attribute omits a verb list entirely).
    [Route("/movies", "POST,PUT,PATCH,DELETE")]
    [Route("/movies/{Id}")]
    public class Movie : IReturn<MovieResponse>
    {
        public int Id { get; set; }
        public string Title { get; set; } = "";
    }

    public class MovieResponse
    {
        public Movie? Result { get; set; }
    }
}
