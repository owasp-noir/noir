## 🛠️ How to Build and Test?
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

## ❤️ Contribute
1. Write code in forked repo
2. Make Pull Request to `dev` branch
3. Finish :D

## 🧭 Code structure
- spec: unit-test codes
- src
  - analyzer: Code analyzers for Endpoint URL and Parameter analysis
  - detector: Codes for language, framework identification 
  - models: Everything for the model, such as class, structure, etc
  - utils: Utility codes
- noir.cr: main and command-line parser
