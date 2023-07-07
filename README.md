#### CFPB Open Source Project Template Instructions

1. Create a new project.
2. [Copy these files into the new project](#installation)
3. Update the README, replacing the contents below as prescribed.
4. Add any libraries, assets, or hard dependencies whose source code will be included
   in the project's repository to the _Exceptions_ section in the [TERMS](TERMS.md).
  - If no exceptions are needed, remove that section from TERMS.
5. If working with an existing code base, answer the questions on the [open source checklist](opensource-checklist.md)
6. Delete these instructions and everything up to the _Project Title_ from the README.
7. Write some great software and tell people about it.

> Keep the README fresh! It's the first thing people see and will make the initial impression.

## Installation

To install all of the template files, run the following script from the root of your project's directory:

```
bash -c "$(curl -s https://raw.githubusercontent.com/CFPB/development/main/open-source-template.sh)"
```

----

# Nostur - a nostr client for Mac, iPhone and iPad

**nostr**: An open protocol: https://github.com/nostr-protocol/nostr
**Nostur**: a social media oriented client for nostr, see https://nostur.com for a a list of features 

**Screenshot**: If the software has visual components, place a screenshot after the description; e.g.,

![](https://nostur.com/screenshots/c/nostur-ui.png)


## Dependencies

- Xcode 14.x
- iOS SDK 16.x

## Setup dev environment

1. Clone this repository
2. Rename Config.xcconfig.dist to Config.xcconfig
3. Enter API keys in Config.xcconfig
4. Open Nostur.xcodeproj in Xcode
5. Run


## Questions / Contact / Feedback

fabian@nostur.com
