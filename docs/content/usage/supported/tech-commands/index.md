+++
title = "Tech Commands"
description = "Guide to using technology-specific commands in Noir to specify which technologies to include or exclude during scanning"
weight = 3
sort_by = "weight"

[extra]
+++

Tech commands allow you to specify and manage the technologies that Noir will use during scanning. You can force the scanner to use specific technologies, exclude certain technologies, or list all available technologies.

```bash
# Force scanning to techs
noir -t rails

# Show all techs
noir --list-techs

#  TECHNOLOGIES:
#    -t TECHS, --techs rails,php      Specify the technologies to use
#    --exclude-techs rails,php        Specify the technologies to be excluded
#    --list-techs                     Show all technologies
```
