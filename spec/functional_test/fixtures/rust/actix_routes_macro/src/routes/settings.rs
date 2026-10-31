use crate::auth::GuardedData;

macro_rules! make_setting_routes {
    ($({route: $route:literal, update_verb: $update_verb:ident, value_type: $type:ty, attr: $attr:ident},)*) => {
        $(
            pub mod $attr {
                use crate::auth::GuardedData;
                use actix_web::HttpResponse;

                pub async fn get(_auth: GuardedData) -> HttpResponse {
                    HttpResponse::Ok().finish()
                }

                pub async fn update(_auth: GuardedData) -> HttpResponse {
                    HttpResponse::Ok().finish()
                }
            }
        )*

        #[routes::routes(
            routes(
                "" => get(get_all),
                $( $route => [get($attr::get), $update_verb($attr::update)]),*
            ),
            tag = "Settings",
        )]
        pub struct SettingsApi;
    };
}

pub async fn get_all(_auth: GuardedData) -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok().finish()
}

make_setting_routes!(
    {
        route: "/dictionary",
        update_verb: put,
        value_type: Vec<String>,
        attr: dictionary,
    },
    {
        route: "/pagination",
        update_verb: patch,
        value_type: std::collections::HashMap<
            String,
            u32,
        >,
        attr: pagination,
    },
);
