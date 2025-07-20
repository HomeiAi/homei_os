# Contributing to Homie OS

We welcome contributions to Homie OS! This document provides guidelines for contributing to the project.

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to [support@homie-ai.com](mailto:support@homie-ai.com).

## How to Contribute

### Reporting Bugs

1. **Check existing issues** - Search the [issue tracker](https://github.com/HomieAiOS/homie_os/issues) to see if the bug has already been reported.

2. **Create a detailed bug report** - Include:
   - Clear description of the problem
   - Steps to reproduce the issue
   - Expected vs actual behavior
   - System information (OS version, hardware, etc.)
   - Relevant logs and error messages

3. **Use the bug report template** when creating new issues.

### Suggesting Features

1. **Check existing feature requests** first.
2. **Open a feature request issue** with:
   - Clear description of the feature
   - Use case and benefits
   - Proposed implementation (if you have ideas)

### Pull Requests

1. **Fork the repository** and create a feature branch from `main`.

2. **Follow the coding standards**:
   - Use meaningful commit messages
   - Follow shell script best practices
   - Add comments for complex logic
   - Test your changes thoroughly

3. **Update documentation** as needed.

4. **Ensure all tests pass** (once we have automated testing).

5. **Create a pull request** with:
   - Clear description of changes
   - Link to related issues
   - Test instructions

## Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/HomieAiOS/homie_os.git
   cd homie_os
   ```

2. **Test in a virtual environment** or on a dedicated Jetson Nano.

3. **Follow the installation guide** in `docs/installation.md`.

## Coding Standards

### Shell Scripts

- Use `#!/bin/bash` shebang
- Use `set -e` for error handling
- Quote variables: `"$variable"`
- Use meaningful function and variable names
- Add error checking and logging
- Follow the existing code style

### Documentation

- Use Markdown format
- Keep line length under 80 characters
- Include code examples where appropriate
- Update table of contents if needed

### Commit Messages

Follow the conventional commit format:
```
type(scope): description

Longer explanation if needed

Fixes #123
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## Testing

Before submitting a pull request:

1. **Test on actual hardware** if possible
2. **Verify scripts run without errors**
3. **Check documentation for accuracy**
4. **Test edge cases and error conditions**

## Release Process

1. Version numbers follow [Semantic Versioning](https://semver.org/)
2. Changes are documented in `CHANGELOG.md`
3. Releases are tagged in Git
4. Release notes include breaking changes and migration guides

## Getting Help

- 📚 [Documentation](docs/)
- 💬 [Discussions](https://github.com/HomieAiOS/homie_os/discussions)
- 📧 [Email](mailto:support@homie-ai.com)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors will be recognized in:
- `CONTRIBUTORS.md` file
- Release notes
- Project documentation

Thank you for contributing to Homie OS! 🚀
