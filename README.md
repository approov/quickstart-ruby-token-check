# Approov QuickStart - Ruby Token Check

[Approov](https://approov.io) is an API security solution used to verify that requests received by your backend services originate from trusted versions of your mobile apps.

This repo implements the Approov server-side request verification code in Ruby (framework agnostic), which performs the verification check before allowing valid traffic to be processed by the API endpoint.


## Approov Integration Quickstart

The quickstart was tested with the following Operating Systems:

* Ubuntu 20.04
* MacOS Big Sur
* Windows 10 WSL2 - Ubuntu 20.04

First, setup the [Appoov CLI](https://approov.io/docs/latest/approov-installation/index.html#initializing-the-approov-cli).

Now, register the API domain for which Approov will issues tokens:

```bash
approov api -add api.example.com
```

Next, enable your Approov `admin` role with:

```bash
eval `approov role admin`
```

Now, get your Approov Secret with the [Appoov CLI](https://approov.io/docs/latest/approov-installation/index.html#initializing-the-approov-cli):

```bash
approov secret -get base64
```

Next, add the [Approov secret](https://approov.io/docs/latest/approov-usage-documentation/#account-secret-key-export) to your project `.env` file:

```env
APPROOV_BASE64_SECRET=approov_base64_secret_here
```

Now, to check the Approov token we will use the [jwt/ruby-jwt](https://github.com/jwt/ruby-jwt) package, that you can install with:

```bash
gem install jwt
```

> **NOTE:** If you are not using yet the `dotenv` package then you also nee to add it to the install command.

Next, add this code to your project:

```ruby
require 'dotenv'
require 'jwt'
require 'base64'

env = Dotenv.parse(".env")

if not env['HTTP_PORT']
    env['HTTP_PORTP'] = 8002
end

if not env['SERVER_HOSTNAME']
    env['SERVER_HOSTNAME'] = '127.0.0.1'
end

if not env['APPROOV_BASE64_SECRET']
    raise "Missing in the .env file the value for the variable: APPROOV_BASE64_SECRET"
end

APPROOV_SECRET = Base64.decode64(env['APPROOV_BASE64_SECRET'])

def verifyApproovToken headers
    begin
        approov_token = headers['approov-token']

        if not approov_token
            # You may want to add some logging here
            return nil
        end

        options = { algorithm: 'HS256' }
        approov_token_claims, header = JWT.decode approov_token, APPROOV_SECRET, true, options

        return approov_token_claims
    rescue JWT::DecodeError => e
        # You may want to add some logging here
        return nil
    rescue JWT::ExpiredSignature => e
        # You may want to add some logging here
        return nil
    rescue JWT::InvalidIssuerError => e
        # You may want to add some logging here
        return nil
    rescue JWT::InvalidIatError
        # You may want to add some logging here
        return nil
    end

    # You may want to add some logging here
    return nil
end
```

Now you just need to invoke `verifyApproovToken()` function for the endpoints you want to protected:

```ruby
if not approov_token_claims = verifyApproovToken(headers)
    sendResponse(connection, 401, JSON.generate({}))
    next
end
```

> **NOTE:** When the Approov token validation fails we return a `401` with an empty body, because we don't want to give clues to an attacker about the reason the request failed, and you can go even further by returning a `400`.

Not enough details in the bare bones quickstart? No worries, check the [detailed quickstarts](QUICKSTARTS.md) that contain a more comprehensive set of instructions, including how to test the Approov integration.


## More Information

* [Approov Overview](OVERVIEW.md)
* [Detailed Quickstarts](QUICKSTARTS.md)
* [Examples](EXAMPLES.md)
* [Testing](TESTING.md)

### System Clock

In order to correctly check for the expiration times of the Approov tokens is very important that the backend server is synchronizing automatically the system clock over the network with an authoritative time source. In Linux this is usually done with a NTP server.

### System Clock

In order to correctly check for the expiration times of the Approov tokens is very important that the backend server is synchronizing automatically the system clock over the network with an authoritative time source. In Linux this is usually done with a NTP server.


## Issues

If you find any issue while following our instructions then just report it [here](https://github.com/approov/quickstart-ruby-token-check/issues), with the steps to reproduce it, and we will sort it out and/or guide you to the correct path.


## Useful Links

If you wish to explore the Approov solution in more depth, then why not try one of the following links as a jumping off point:

* [Approov Free Trial](https://approov.io/signup)(no credit card needed)
* [Approov Get Started](https://approov.io/product/demo)
* [Approov QuickStarts](https://approov.io/docs/latest/approov-integration-examples/)
* [Approov Docs](https://approov.io/docs)
* [Approov Blog](https://approov.io/blog/)
* [Approov Resources](https://approov.io/resource/)
* [Approov Customer Stories](https://approov.io/customer)
* [Approov Support](https://approov.io/contact)
* [About Us](https://approov.io/company)
* [Contact Us](https://approov.io/contact)
