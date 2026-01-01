# Sample Python file for testing source code comment tagger

from flask import Flask, request

app = Flask(__name__)

# @deprecated - This endpoint will be removed in v2
@app.route('/api/v1/old_endpoint', methods=['GET'])
def old_endpoint():
    return "This is deprecated"

# Admin only endpoint
# @admin
@app.route('/admin/users', methods=['GET'])
def admin_users():
    # requires_admin
    return get_all_users()

# Internal use only
# @internal
@app.route('/internal/health', methods=['GET'])
def health_check():
    # INTERNAL_ONLY
    return {"status": "ok"}

# Authentication required
# @login_required
@app.route('/api/profile', methods=['GET'])
def get_profile():
    return get_current_user()

# Rate limited endpoint
# @rate_limit(requests=100, period=60)
@app.route('/api/search', methods=['GET'])
def search():
    return do_search()

# Cached response
# @Cacheable
@app.route('/api/products', methods=['GET'])
def get_products():
    return get_all_products()

# TODO: fix security issue with this endpoint
@app.route('/api/vulnerable', methods=['POST'])
def vulnerable_endpoint():
    # FIXME: add proper authentication
    return process_data()








































# Regular endpoint without special annotations
# This endpoint has no security annotations
# It is a simple public API endpoint
@app.route('/api/public', methods=['GET'])
def public_endpoint():
    return {"message": "Hello World"}
