# intellinote-cli

A simple Node.js-based command-line client to the Intellinote REST API.

## Installing

### Via npm

intellinote-cli is deployed as an [npm module](https://npmjs.org/) under the name [`intellinote-cli`](https://npmjs.org/package/intellinote-cli). Hence you can install a pre-packaged version with the command:

```bash
npm install -g intellinote-cli
```

Omit the `-g` part to install the module "locally" (in the current working directory).

Once installed, the command `intellinote` should be available in your `node_modules/.bin` directory.

### For use as a library

You can use intellinote-cli within your Node.js module by adding a line like:

```javascript
"intellinote-cli": "latest"
```

to the `dependencies` or `devDependencies` part of your `package.json` file.

### From source

The source code and documentation for intellinote-cli is available on GitHub at [intellinote/intellinote-cli](https://github.com/intellinote/intellinote-cli).  You can clone the repository via:

```bash
git clone git@github.com:intellinote/intellinote-cli
```

Once the code is obtain, you can run:

```bash
make install bin
```

to install any dependencies and build the executeable script.

Once installed, the command `intellinote` should be available in the `intellinote-cli/bin` directory.

## Using

### help

Invoke `intellinote` with the command line parameter `--help` for a quick usage summary:

```bash
$ ./bin/intellinote --help
USE: intellinote login|logout|(GET|POST|PUT|PATCH|DELETE|HEAD <URL> [<BODY>])
```

### "Raw" API calls

intellinote-cli provides a simple way to invoke [Intellinote's REST API](https://api.intellinote.net/) using the following form:

    intellinote <HTTP-VERB> <PATH> [<BODY>]

For example, the following command invokes the REST method `/v2.0/ping` (which returns a timestamp):

```bash
$ ./bin/intellinote GET /v2.0/ping"
{"timestamp":1423504162750}
```

### login

Before you can use intellinote-cli you must authenticate to Intellinote using the `login` command.

intellinote-cli ask you for your username and password and then use the OAuth2 protocol to exchange those credentials for an "access token"

```bash
$ ./bin/intellinote login
Username? jane.doe@example.com
Password? ********
```

intellinote-cli does NOT store your username and password.  It does however store the access token value in a file located at `$HOME/.intellinote`.  In a limited sense, that access token can be used much like a password.  You should keep that file secure.

### logout

Invoking `intellinote logout` will remove all log-in information from the configuration file at `$HOME/.intellinote`.  You will need to log in again to access your Intellinote data.

## Licensing

The intellinote-cli library and related documentation are made available
under an [MIT License](http://opensource.org/licenses/MIT).  For details, please see the file [LICENSE.txt](LICENSE.txt) in the root directory of the repository.

## How to contribute

Your contributions, [bug reports](https://github.com/intellinote/intellinote-cli/issues) and [pull-requests](https://github.com/intellinote/intellinote-cli/pulls) are greatly appreciated.

We're happy to accept any help you can offer, but the following
guidelines can help streamline the process for everyone.

 * You can report any bugs at
   [github.com/intellinote/intellinote-cli/issues](https://github.com/intellinote/intellinote-cli/issues).

    - We'll be able to address the issue more easily if you can
      provide an demonstration of the problem you are
      encountering. The best format for this demonstration is a
      failing unit test (like those found in
      [./test/](https://github.com/intellinote/intellinote-cli/tree/master/test)), but
      your report is welcome with or without that.

 * Our preferred channel for contributions or changes to the
   source code and documentation is as a Git "patch" or "pull-request".

    - If you've never submitted a pull-request, here's one way to go
      about it:

        1. Fork or clone the repository.
        2. Create a local branch to contain your changes (`git
           checkout -b my-new-branch`).
        3. Make your changes and commit them to your local repository.
        4. Create a pull request [as described here](
           https://help.github.com/articles/creating-a-pull-request).

    - If you'd rather use a private (or just non-GitHub) repository,
      you might find
      [these generic instructions on creating a "patch" with Git](https://ariejan.net/2009/10/26/how-to-create-and-apply-a-patch-with-git/)
      helpful.

 * If you are making changes to the code please ensure that the
   [unit test suite](./test) still passes.

 * If you are making changes to the code to address a bug or introduce
   new features, we'd *greatly* appreciate it if you can provide one
   or more [unit tests](./test) that demonstrate the bug or
   exercise the new feature.

**Please Note:** We'd rather have a contribution that doesn't follow
these guidelines than no contribution at all.  If you are confused
or put-off by any of the above, your contribution is still welcome.
Feel free to contribute or comment in whatever channel works for you.

---

[![Intellinote](https://www.intellinote.net/wp-content/themes/intellinote/images/logo@2x.png)](https://www.intellinote.net/)

## About Intellinote

Intellinote is a multi-platform (web, mobile, and tablet) software
application that helps businesses of all sizes capture, collaborate
and complete work, quickly and easily.

Users can start with capturing any type of data into a note, turn it
into a task, assign it to others, start a discussion around it, add a
file and share – with colleagues, managers, team members, customers,
suppliers, vendors and even classmates. Since all of this is done in
the context of private and public workspaces, users retain end-to-end
control, visibility and security.

For more information about Intellinote, visit
<https://www.intellinote.net/>.

### Work with Us

Interested in working for Intellinote?  Visit
[the careers section of our website](https://www.intellinote.net/careers/)
to see our latest technical (and non-technical) openings.

---
