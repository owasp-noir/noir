use axum::extract::State;

pub async fn get(State(body): State<String>) -> String {
    body
}
