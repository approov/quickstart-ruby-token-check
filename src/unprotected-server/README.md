# Unprotected Server Example

The unprotected example is the base reference to build the [Approov protected servers](/src/approov-protected-server/). This a very basic Hello World server.


## TOC - Table of Contents

* [Why?](#why)
* [How it Works?](#how-it-works)
* [Requirements](#requirements)
* [Try It](#try-it)


## Why?

To be the starting building block for the [Approov protected servers](/src/approov-protected-server/), that will show you how to lock down your API server to your mobile app. Please read the brief summary in the [Approov Overview](/OVERVIEW.md#why) at the root of this repo or visit our [website](https://approov.io/product) for more details.

[TOC](#toc---table-of-contents)


## How it works?

The Ruby server is very simple and is defined in the file [src/unprotected-server/hello-server-unprotected.rb](/src/unprotected-server/hello-server-unprotected.rb).

The server only replies to the endpoint `/` with the message:

```json
{"message": "Hello, World!"}
```

[TOC](#toc---table-of-contents)


## Requirements

To run this example you will need to have Ruby installed. If you don't have then please follow the official installation instructions from [here](https://www.ruby-lang.org/en/documentation/installation/) to download and install it.

[TOC](#toc---table-of-contents)


## Try It

First, install the `dotenv` package to read the `.env` file.

```bash
gem install dotenv
```

Now, run this example from the `src/unprotected-server` folder with:

```bash
ruby hello-server-unprotected.rb
```

Finally, you can test that it works with:

```bash
curl -iX GET 'http://localhost:8002'
```

The response will be:

```text
HTTP/1.1 200
Content-Type: application/json
Content-Length: 27

{"message":"Hello, World!"}
```

[TOC](#toc---table-of-contents)


## Issues

If you find any issue while following our instructions then just report it [here](https://github.com/approov/quickstart-ruby-token-check/issues), with the steps to reproduce it, and we will sort it out and/or guide you to the correct path.

[TOC](#toc---table-of-contents)


## Useful Links

If you wish to explore the Approov solution in more depth, then why not try one of the following links as a jumping off point:

* [Approov Free Trial](https://approov.io/signup)(no credit card needed)
* [Approov Get Started](https://approov.io/product/demo)
* [Approov QuickStarts](https://approov.io/docs/latest/approov-integration-examples/)
* [Approov Docs](https://approov.io/docs)
* [Approov Blog](https://approov.io/blog/)
* [Approov Resources](https://approov.io/resource/)
* [Approov Customer Stories](https://approov.io/customer)
* [Approov Support](https://approov.zendesk.com/hc/en-gb/requests/new)
* [About Us](https://approov.io/company)
* [Contact Us](https://approov.io/contact)

[TOC](#toc---table-of-contents)
