# AI Agent Guidelines for This Project

This document provides guidelines for an AI agent to understand and work with this project.

## Project Structure Overview

The project is organized into several key directories:

*   **`src/`**: Contains the main source code of the application.
    *   `src/analyzer/`: Houses code for analyzing source code to find endpoints, routes, etc.
    *   `src/detector/`: Contains code for detecting frameworks and technologies.
    *   `src/output_builder/`: Holds logic for formatting the output in various forms (JSON, YAML, cURL, etc.).
    *   `src/models/`: Defines data structures and models used throughout the application.
    *   `src/llm/`: Contains code related to Large Language Model integrations.
    *   `src/minilexers/` and `src/miniparsers/`: Likely contain custom lexing and parsing utilities for specific languages or formats.
    *   `src/tagger/`: Code for tagging or categorizing discovered endpoints.
    *   `src/deliver/`: Code related to sending processed data to external tools or proxies.
*   **`spec/`**: Contains all the tests for the project.
    *   `spec/functional_test/`: Holds functional tests, which test the application's behavior from an end-user perspective.
        *   `spec/functional_test/fixtures/`: Contains sample code or project files used as input for functional tests.
        *   `spec/functional_test/testers/`: Contains the actual test scripts for functional tests.
    *   `spec/unit_test/`: Holds unit tests, which test individual components or modules in isolation.
*   **`docs/`**: Contains project documentation, likely generated using Hugo (based on `hugo.toml` and `docs/content/`). This is a good place to look for more detailed information about features and usage.
*   **`shard.yml`**: (Crystal specific) Declares project dependencies and metadata. This is crucial for understanding how the project is built and what libraries it uses.
*   **`justfile`**: Contains definitions for common project commands, making it easier to build, test, and run the application. Examine this file to learn about available commands.

## Development Workflows

### Adding a New Analyzer

Analyzers are responsible for parsing source code to identify API endpoints, routes, and other relevant information. When adding a new analyzer (e.g., for a new language or framework):

1.  **Create the Analyzer File:**
    *   Place the new analyzer code in the `src/analyzer/analyzers/` directory.
    *   Organize by language. For example, a Crystal-based analyzer for the Kemal framework would be at `src/analyzer/analyzers/crystal/kemal.cr`.
    *   Refer to existing analyzers (like `src/analyzer/analyzers/example.cr` or others in specific language directories) for structure and coding style. Analyzers typically inherit from a base analyzer class and implement specific parsing logic.

2.  **Add Functional Tests:**
    *   Create corresponding test files in `spec/functional_test/testers/`.
    *   Maintain a similar directory structure based on language. For the Kemal example, the test would be `spec/functional_test/testers/crystal/kemal_spec.cr`.
    *   Write tests to verify that your analyzer correctly identifies endpoints from sample code.

3.  **Provide Fixture/Example Files:**
    *   Create a directory for your analyzer's fixtures under `spec/functional_test/fixtures/`.
    *   Again, organize by language. For the Kemal example, this would be `spec/functional_test/fixtures/crystal/kemal/`.
    *   Add example source code files within this directory that your tests will use. These files should contain the patterns your analyzer is designed to detect.

4.  **Update Configuration (if necessary):**
    *   Some analyzers might need to be registered or configured in a central place. Check if there's a main analyzer registry or configuration file that needs updating to include your new analyzer. (Explore `src/analyzer/analyzer.cr` or similar).

5.  **Run Tests:**
    *   Execute the test suite to ensure your new analyzer works as expected and doesn't break existing functionality. Refer to the `justfile` for commands to run tests.

6.  **Update Documentation and Tech List:**
    *   After creating the analyzer and its tests, update `docs/content/docs/usage/supported/language_and_frameworks.md` to reflect the support for the new language or framework.
    *   If the analyzer is for a specific API specification (e.g., OpenAPI, RAML), also update `docs/content/docs/usage/supported/specification.md`.
    *   Add/update the corresponding entry in `src/techs/techs.cr` so that the new technology is listed when using the `--list-techs` command.

### Adding a New Detector

Detectors are used to identify the technologies, frameworks, or languages used in a project. This information can then be used to select the appropriate analyzers.

1.  **Create the Detector File:**
    *   Place the new detector code in the `src/detector/detectors/` directory.
    *   Organize by language or technology type if applicable. For example, a detector for a specific Crystal framework would go into `src/detector/detectors/crystal/`.
    *   Refer to `src/detector/detectors/detector_example.cr` and other existing detectors for the expected structure and coding conventions. Detectors usually implement a common interface or inherit from a base class.

2.  **Add Unit Tests:**
    *   Create corresponding unit test files in `spec/unit_test/detector/`.
    *   Maintain a similar directory structure (e.g., `spec/unit_test/detector/crystal/my_framework_detector_spec.cr`).
    *   Write tests to verify that your detector correctly identifies the technology based on file contents, project structure, or other indicators.

3.  **Provide Fixture/Example Files (if applicable):**
    *   If your detector relies on specific file patterns or contents, you might need to add fixture files. These could reside in a structure similar to analyzer fixtures (e.g., `spec/functional_test/fixtures/crystal/my_framework_for_detector/`) or within the unit test directory if they are small and specific to a few tests.

4.  **Update Configuration (if necessary):**
    *   Check if detectors need to be registered in a central location (e.g., `src/detector/detector.cr` or a similar registry file).

5.  **Run Tests:**
    *   Execute the test suite to ensure your new detector works correctly.

6.  **Update Documentation and Tech List:**
    *   After creating the detector and its tests, update `docs/content/docs/usage/supported/language_and_frameworks.md` to reflect the support for the new language or framework.
    *   If the detector is for a specific API specification (e.g., OpenAPI, RAML), also update `docs/content/docs/usage/supported/specification.md`.
    *   Add/update the corresponding entry in `src/techs/techs.cr` so that the new technology is listed when using the `--list-techs` command.

### Adding a New Output Builder

Output builders format the data extracted by analyzers into different output formats (e.g., JSON, YAML, cURL commands, Markdown tables).

1.  **Create the Output Builder File:**
    *   Place the new output builder code directly in the `src/output_builder/` directory (e.g., `src/output_builder/my_new_format.cr`).
    *   Examine existing output builders (e.g., `src/output_builder/json.cr`, `src/output_builder/curl.cr`) to understand the required interface and structure. They usually process a list of identified endpoints or other data structures.

2.  **Add Unit Tests:**
    *   Create corresponding unit test files in `spec/unit_test/output_builder/` (e.g., `spec/unit_test/output_builder/my_new_format_spec.cr`).
    *   Write tests to ensure your output builder correctly formats the input data into the desired output string or structure.

3.  **Update Configuration (if necessary):**
    *   The application will need to know about the new output format. This might involve:
        *   Adding a new command-line option to specify the output format.
        *   Updating a central dispatcher or factory that selects the output builder based on user input. (Explore `src/options.cr` or how output formats are handled in the main application logic).

4.  **Run Tests:**
    *   Execute the test suite.

## General Advice for AI Agent

*   **Identifying Language/Framework:** The directory structure within `src/analyzer/analyzers/`, `src/detector/detectors/`, `spec/functional_test/testers/`, and `spec/functional_test/fixtures/` often indicates the programming language or framework a component is related to (e.g., `crystal/`, `go/`, `python/`).
*   **Dependencies (`shard.yml`):** This project is written in Crystal. The `shard.yml` file at the root lists all project dependencies. If you need to understand which libraries are used, this is the primary file to check. For installing or updating dependencies, you'd typically use the `shards` command (Crystal's dependency manager).
*   **Common Commands (`justfile`):** The `justfile` in the project root contains recipes for common tasks such as running tests, building the project, linting, etc. Use `just --list` (if `just` is installed) to see available commands, or simply inspect the file contents. This is often the preferred way to execute routine tasks. See the "Building and Testing" section below for specific examples.
*   **Building and Testing:**
    *   **With `just` (recommended):**
        *   Build: `just build`
        *   Test: `just test`
    *   **Without `just` (manual Crystal commands):**
        *   Build: `shards build` (this will also install dependencies)
        *   Test: `crystal spec` (run this after building)
*   **Further Documentation (`docs/`):** The `docs/` directory contains more detailed project documentation. If you need to understand specific features, advanced usage, or contribution guidelines in more depth, explore the content within `docs/content/docs/`.
*   **Coding Style:** When adding new code, try to match the style and conventions of existing code in the same module or directory. Pay attention to naming conventions, formatting, and commenting practices.
*   **Testing is Key:** Always add tests for new functionality. Ensure all tests pass before considering a task complete.
*   After completing code modifications, always verify that the project builds successfully and that all tests pass.
*   Strive to write new code that aligns with the existing code's structure, patterns, and style.
