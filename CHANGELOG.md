# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial release
- Core agent framework with `Glossia.Agent` behaviour
- Session management with `Glossia.Agent.Session` GenServer
- Message types: user, assistant, tool_result
- Provider abstraction with Anthropic Claude support
- Built-in tools: Read, Bash, Edit, Write
- Streaming support with real-time events
- Telemetry integration for observability
- Extended thinking support for Claude models
