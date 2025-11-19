# JavaScript Analyzer Improvements - Advanced Test Fixtures

This directory contains comprehensive test fixtures for JavaScript frameworks, following the approach from PR #817 which improved Go analyzers.

## Overview

Added advanced test fixtures for all 5 JavaScript frameworks to test various coding patterns and modern JavaScript/TypeScript syntax:

- **Express** (`express_advanced/advanced_patterns.js`)
- **Fastify** (`fastify_advanced/advanced_patterns.js`)
- **Koa** (`koa_advanced/advanced_patterns.js`)
- **NestJS** (`nestjs_advanced/advanced_patterns.ts`)
- **Restify** (`restify_advanced/advanced_patterns.js`)

## Test Patterns Included

Each test fixture includes patterns for:

1. **Case-insensitive HTTP Methods**
   - `.Get()`, `.Post()`, `.PUT()`, `.Delete()`, `.Patch()`
   - Common in TypeScript and ES6+ code

2. **Multi-line Route Definitions**
   - Routes split across multiple lines
   - Routes with extensive middleware chains
   - Formatted code with line breaks

3. **Async/Await Patterns**
   - Modern async route handlers
   - Promise-based middleware
   - Async arrow functions

4. **Path Parameters**
   - Nested path parameters (`:userId/posts/:postId`)
   - Optional parameters (`:id?`)
   - Wildcard routes (`*`)

5. **Parameter Extraction Patterns**
   - Destructuring: `const { field1, field2 } = req.body`
   - Direct access: `req.body.field`
   - Bracket notation: `req.body['field']`
   - Query params: `req.query.param`
   - Headers: `req.headers['x-custom']`, `req.header('X-Custom')`
   - Cookies: `req.cookies.sessionId`

6. **Template Literals and Concatenation**
   - Template literal paths: `` `${prefix}/users` ``
   - String concatenation: `prefix + '/users'`

7. **Nested Routers**
   - Router with prefix registration
   - Plugin-based routes (Fastify)
   - Router.use() patterns (Express/Restify)

8. **Method Chaining**
   - `app.route('/path').get(...).post(...)`
   - Multiple methods on same route

9. **Framework-Specific Patterns**
   - Fastify: Plugin registration, schemas, hooks
   - Koa: Context (`ctx`) access patterns, Router
   - NestJS: Decorators (`@Get`, `@Post`, `@Controller`)
   - Restify: Named routes, versioned routes
   - Express: Router nesting, middleware chains

## Current Analyzer Support

### ✅ Currently Detected Patterns

- Multi-line route definitions
- Nested path parameters
- Parameter extraction (destructuring, direct access)
- Template literal paths
- String concatenated paths
- Basic async/await patterns

### 🔨 Needs Improvement

The following patterns are in the test fixtures but not yet fully detected by all analyzers:

1. **Case-insensitive methods** - Methods like `.Get()`, `.Post()` need better detection
2. **Arrow function route handlers** - Some patterns not detected
3. **Nested router prefixes** - Complex router.use() patterns
4. **Plugin-based routes** - Fastify plugin registration with prefixes
5. **Named and versioned routes** - Restify-specific features
6. **Multi-line middleware chains** - Routes with multiple middleware functions
7. **Decorator parameters** - NestJS multi-line decorators

## Usage

These test fixtures serve as:

1. **Documentation** - Examples of real-world coding patterns
2. **Future Test Cases** - When analyzers are improved, these can be added to test specs
3. **Benchmarking** - Measure analyzer coverage improvements over time

## Testing

To test detection with current analyzers:

```bash
# Express advanced patterns
./bin/noir -b spec/functional_test/fixtures/javascript/express_advanced/

# Fastify advanced patterns
./bin/noir -b spec/functional_test/fixtures/javascript/fastify_advanced/

# Koa advanced patterns
./bin/noir -b spec/functional_test/fixtures/javascript/koa_advanced/

# NestJS advanced patterns
./bin/noir -b spec/functional_test/fixtures/javascript/nestjs_advanced/

# Restify advanced patterns
./bin/noir -b spec/functional_test/fixtures/javascript/restify_advanced/
```

## Related Work

- PR #817: Improved Go analyzer detection for case-insensitive methods and multi-line definitions
- Similar approach: Add comprehensive test fixtures first, then improve analyzers incrementally

## Future Improvements

Priority improvements for JavaScript analyzers:

1. Enhance JS parser (`miniparsers/js_route_extractor.cr`) to handle case-insensitive methods
2. Improve multi-line pattern detection across all analyzers
3. Better plugin/router prefix resolution
4. Enhanced parameter extraction from complex destructuring patterns
5. Framework-specific feature support (versioning, named routes, etc.)
