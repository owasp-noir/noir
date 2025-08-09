# AI Agent Contributor Guidelines

This document provides guidelines for an AI agent to understand the project structure and contribute effectively to the codebase.

---

## 🚀 Getting Started: Guiding Principles

Before making any code changes, please adhere to these core principles:

* **Testing is Mandatory:** Every new feature or fix must be accompanied by relevant tests. Consider writing tests before writing the new code.
* **Follow Existing Patterns:** When adding new code, imitation is the best approach. Consistently follow the structure, naming conventions, and coding style of existing code.
* **Documentation is Key:** When adding new features (like an Analyzer or Detector), you must also update the relevant documentation and the technology list (`techs.cr`).
* **Leverage the `justfile`:** It's best to use the commands defined in the `justfile` for common tasks like building, testing, and linting the project.

---

## 📂 Project Structure

The project is organized into the following key directories:

* `src/`: Contains the core source code of the application.
    * `analyzer/`: Analyzers that parse source code to find endpoints, routes, etc.
    * `detector/`: Detectors that identify the frameworks and technologies used.
    * `output_builder/`: Logic for formatting the analysis results into various formats (JSON, YAML, cURL, etc.).
    * `models/`: Data models and structures used throughout the application.
    * `llm/`: Code related to Large Language Model (LLM) integration.
    * `tagger/`: Code for tagging or categorizing discovered endpoints.
    * `deliver/`: Code for sending processed data to external tools or proxies.
* `spec/`: Contains all test code.
    * `functional_test/`: End-to-end functional tests from a user's perspective.
        * `fixtures/`: Sample code and project files used as input for functional tests.
        * `testers/`: The actual functional test scripts.
    * `unit_test/`: Unit tests for individual modules in isolation.
* `docs/`: Project documentation, generated with Zola. A good place to find detailed information about features and usage.
* `shard.yml`: (Crystal) Declares project dependencies and metadata. This is the most crucial file for understanding the libraries the project uses.
* `justfile`: Defines common project commands for building, testing, etc. Inspect this file to learn about available commands.

---

## 💻 Development Workflows

### Adding a New Analyzer

1.  **Create Analyzer File:** Create the file in a language-specific subdirectory within `src/analyzer/analyzers/` (e.g., `src/analyzer/analyzers/crystal/kemal.cr`).
    * Refer to existing Analyzers (like `example.cr`) for structure and style.
2.  **Add Functional Test:** Create a corresponding test file in `spec/functional_test/testers/` using the same path structure (e.g., `spec/functional_test/testers/crystal/kemal_spec.cr`).
    * Tests should verify that your analyzer correctly identifies endpoints from sample code.
3.  **Provide Fixture File:** Add sample source code files for your tests under `spec/functional_test/fixtures/` (e.g., `spec/functional_test/fixtures/crystal/kemal/`).
4.  **Register Analyzer (if needed):** Check and update a central registry file, such as `src/analyzer/analyzer.cr`, to register your new analyzer.
5.  **Run Tests & Update Docs:**
    * Run the full test suite to ensure no regressions. (`just test`)
    * **Important:** Add the newly supported technology to `docs/content/docs/usage/supported/language_and_frameworks.md` and `src/techs/techs.cr`.

### Adding a New Detector

1.  **Create Detector File:** Place the new file in `src/detector/detectors/` (e.g., `src/detector/detectors/crystal/my_framework.cr`).
    * Refer to `detector_example.cr` and other existing Detectors for the required interface and conventions.
2.  **Add Unit Test:** Create a test file in `spec/unit_test/detector/` (e.g., `spec/unit_test/detector/crystal/my_framework_detector_spec.cr`).
    * Tests should verify that the detector correctly identifies the technology based on file content or project structure.
3.  **Register Detector (if needed):** Check the central registry file (e.g., `src/detector/detector.cr`) and add your new detector.
4.  **Run Tests & Update Docs:**
    * Run the full test suite. (`just test`)
    * **Important:** Update `docs/content/docs/usage/supported/language_and_frameworks.md` and `src/techs/techs.cr`.

### Adding a New Output Builder

1.  **Create Builder File:** Place the new file in the `src/output_builder/` directory (e.g., `src/output_builder/my_new_format.cr`).
    * Examine existing builders like `json.cr` or `curl.cr` to implement the required interface.
2.  **Add Unit Test:** Create a test file in `spec/unit_test/output_builder/` (e.g., `spec/unit_test/output_builder/my_new_format_spec.cr`).
    * Tests should verify that the builder correctly formats input data into the desired output.
3.  **Update Options & Logic:** Modify the application logic (e.g., the command-line option handler in `src/options.cr`) to recognize the new output format.
4.  **Run Tests:** Run the full test suite to confirm everything works as expected.

---

## 🛠️ Building & Testing

It is highly recommended to use `just` for all tasks.

* **List available commands:**
    ```
    just --list
    ```
* **Build the project:**
    ```
    just build
    ```
* **Run tests:**
    ```
    just test
    ```
* **Manual execution (without `just`):**
    ```
    shards install # Install dependencies
    shards build   # Build
    crystal spec   # Run tests
    ```

After finishing your work, always verify that the project builds successfully and that all tests pass.
