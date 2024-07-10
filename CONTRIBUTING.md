# ❤️ Contribution Guidelines

Thank you for considering contributing to our project! Here are some guidelines to help you get started and ensure a smooth contribution process.

1. Fork and Code
- Begin by forking the repository.
- Write your code within your forked repository.

3. Pull Request
- Once your contribution is ready, create a Pull Request (PR) to the dev branch of the main repository.
- Provide a clear and concise description of your changes in the PR.

4. Completion
- That's it! You're done. Await feedback and further instructions from the maintainers.

![](https://github.com/hahwul/noir/assets/13212227/23989dab-6b4d-4f18-904f-7f5cfd172b04)

## 🛠️ Building and Testing
### Clone and Install Dependencies

```bash
# If you've forked this repository, clone to https://github.com/<YOU>/noir
git clone https://github.com/hahwul/noir
cd noir
shards install
```

### Build
```bash
shards build
# ./bin/noir
```

### Unit/Functional Test
```bash
crystal spec

# If you want more detail?
crystal spec -v
```

### Lint
```bash
crystal tool format
ameba --fix

# Ameba installation
# https://github.com/crystal-ameba/ameba#installation
```

## 🧭 Code structure

- spec: 
  - unit_test: Unit test codes. (for `crystal spec` command)
  - functional_test: Functional test codes.
- src: Contains the source code.
  - analyzer: Code analyzers for Endpoint URL and Parameter analysis.
  - detector: Codes for language and framework identification.
  - models: Contains everything related to models, such as classes and structures.
- noir.cr: Main file and command-line parser.

Feel free to reach out to us if you have any questions or need further assistance!

## Documents contributing

Please note that [our web page](https://owasp-noir.github.io/noir/) operates based on the dev branch. If you make any changes, kindly send a Pull Request (PR) to the dev branch. 

To ensure a smooth integration of your contributions, please follow these steps:

* Fork the repository and create your feature branch from dev.
* Make your changes, ensuring they are thoroughly tested.
* Submit your PR to the dev branch for review.

By doing so, you'll help us keep our project up-to-date and well-organized. Your efforts are greatly appreciated, and we're excited to see what you'll bring to the project!