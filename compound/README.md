# Compound

Compound is an application for building compound process scripts and viewing the output of them.

## Usage

### compound.json

At the root of your project create a `compound.json` file and specify the processes you want to run.

The following example runs an `air` and a `npx vite` command in two separate relative directories.

```json
[
    {
        "name": "backend",
        "process": {
            "command": "air",
            "args": [],
            "cwd": "../backend"
        }
    },
    {
        "name": "frontend",
        "process": {
            "command": "npx",
            "args": [
                "vite"
            ],
            "cwd": "../frontend"
        }
    }
]
```

### Launching

Simply run `compound` in the same folder you created your `compound.json` and watch it go.
