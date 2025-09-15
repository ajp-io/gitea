# Gitea for Replicated

A Gitea deployment package for [Replicated](https://replicated.com), enabling easy installation and management of Gitea through the Replicated platform.

Gitea is a lightweight code hosting solution. Written in Go, features low resource consumption, easy upgrades and multiple databases.

[Overview of Gitea](https://gitea.io/)

## Overview

This package provides a complete Gitea deployment for Kubernetes environments using Replicated's application distribution platform. It includes:

- Pre-configured Gitea deployment with PostgreSQL database
- Integrated configuration management through KOTS
- Support for airgap installations
- Embedded cluster compatibility

## Installation

This application is designed to be installed through Replicated's distribution platform:

1. **Embedded Cluster**: Deploy as a complete Kubernetes cluster with Gitea included
2. **Existing Cluster**: Install into an existing Kubernetes cluster using KOTS
3. **Helm**: Install directly using Helm charts in supported environments

## Configuration

Configuration is managed through the Replicated Admin Console, which provides a web-based interface for:

### Gitea Settings
- **Admin Username**: Set the initial Gitea administrator username
- **Admin Password**: Set the initial Gitea administrator password
- **Admin Email**: Configure the administrator email address

### Database Configuration
- **Database Type**: Choose between embedded PostgreSQL or external database
- **Embedded PostgreSQL**: Configure username, password, and database name for the built-in database
- **External PostgreSQL**: Connect to an existing PostgreSQL server with host, database, credentials, and schema settings
- **High Availability**: Enable HA mode for the embedded PostgreSQL (when using embedded option)

## Components

This package includes:

- **Gitea**: The main Git hosting application
- **PostgreSQL**: Database backend for Gitea
- **KOTS Configuration**: Replicated-specific configuration management
- **Embedded Cluster Support**: Complete Kubernetes distribution option

## Requirements

### For Existing Kubernetes Clusters
- Kubernetes 1.23+
- KOTS installed
- Sufficient storage for Git repositories and database

### For Embedded Cluster
- Supported Linux distribution
- Minimum system requirements as defined in embedded cluster configuration

## Support

This Gitea package is distributed through Replicated. For support:

- Contact your Replicated administrator
- Refer to [Gitea documentation](https://docs.gitea.com/) for application-specific questions
- Check [Replicated documentation](https://docs.replicated.com/) for platform-specific issues

## License

This Gitea package is subject to Gitea's MIT license and Replicated's terms of service.