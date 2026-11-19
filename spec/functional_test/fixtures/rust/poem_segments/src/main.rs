use poem::{delete, handler, web::Path, Route};
use poem_openapi::{payload, OpenApi};

#[handler]
fn remove(Path(id): Path<u32>) -> String { id.to_string() }

struct PetApi;

#[OpenApi]
impl PetApi {
    #[oai(path = "/pets", method = "post")]
    async fn create_pet(&self, pet: payload::Json<String>) -> payload::PlainText<String> {
        payload::PlainText(pet.0)
    }
}

fn app() -> Route {
    // `<\d+>` constrains the segment; it is not part of the URL.
    Route::new().at("/items/:id<\\d+>", delete(remove))
}
