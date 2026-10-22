use ntex::web;

// Nested tuple services, the layout ntex's own examples use.
pub fn config_app(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/products").service((
            web::resource("")
                .route(web::get().to(get_products))
                .route(web::post().to(add_product)),
            web::scope("/{product_id}").service((
                web::resource("")
                    .route(web::get().to(get_product_detail))
                    .route(web::delete().to(remove_product)),
                web::scope("/parts").service((
                    web::resource("/{part_id}").route(web::get().to(get_part_detail)),
                )),
            )),
        )),
    );
}

async fn get_products(_query: web::types::Query<Filter>) -> web::HttpResponse {
    web::HttpResponse::Ok().finish()
}

async fn add_product(_new_product: web::types::Json<Product>) -> web::HttpResponse {
    web::HttpResponse::Created().finish()
}

async fn get_product_detail(_id: web::types::Path<String>) -> web::HttpResponse {
    web::HttpResponse::Ok().finish()
}

async fn remove_product(_id: web::types::Path<String>) -> web::HttpResponse {
    web::HttpResponse::Ok().finish()
}

async fn get_part_detail(_id: web::types::Path<(String, String)>) -> web::HttpResponse {
    web::HttpResponse::Ok().finish()
}

#[derive(serde::Deserialize)]
pub struct Filter {
    pub name: Option<String>,
}

#[derive(serde::Deserialize)]
pub struct Product {
    pub name: String,
}
