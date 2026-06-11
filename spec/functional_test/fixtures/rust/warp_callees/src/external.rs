pub async fn create_external(user: crate::CreateUser) -> Result<impl warp::Reply, warp::Rejection> {
    let created = ExternalService::create(user);
    AuditLog::write_external();
    Ok(UserPresenter::render(created))
}
