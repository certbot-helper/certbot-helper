# Certbot Helper Script

## Introduction

The Certbot Helper Script is a convenient tool designed to streamline the process of obtaining SSL certificates for your domain using Certbot. It supports both Apache and Nginx web servers and ensures that your server is properly configured with a valid SSL certificate. Additionally, it sets up a basic `index.php` file in your domain's root directory to confirm the successful setup.

## Features

- Supports both Apache and Nginx web servers.
- Automatically installs Certbot and necessary plugins if not already installed.
- Configures your web server with SSL certificates.
- Creates a default `index.php` file in your domain's root directory.
- Provides clear error handling and instructions for troubleshooting.

## Prerequisites

- A domain name pointing to your server.
- Root or sudo access to your server.

## Installation

1. Clone this repository to your server:
   ```sh
   git clone https://github.com/VeloxityNL/certbot-helper.git
   cd certbot-helper
   ```

2. Make the script executable:
   ```sh
   chmod +x certbot-helper.sh
   ```

## Usage

1. Run the script:
   ```sh
   sudo ./certbot-helper.sh
   ```

2. Follow the prompts:
   - Enter your web server type (`apache` or `nginx`).
   - Provide your domain name.

3. The script will:
   - Install Certbot and necessary plugins if not already installed.
   - Obtain an SSL certificate for your domain.
   - Configure your web server with the obtained certificate.
   - Create a default `index.php` file in your domain's root directory.

4. Check the output for any errors and ensure your website is properly set up with SSL.

## Example

```
sudo ./certbot-helper.sh

Which web server are you using? (apache/nginx)
> nginx

For which domain do you want to create a certificate? E.g: domain.com
> example.com
```

After running the script, your Nginx configuration for the domain will be set up, and a default `index.php` file will be created in `/var/www/example.com`.

## Troubleshooting

If the script encounters any errors during execution, it will provide detailed error messages and cleanup any partial configurations to ensure your server remains in a stable state.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## Contact

For any questions or support, please open an issue in the repository.

