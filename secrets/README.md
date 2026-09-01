# secrets/

Values that must never reach GitHub.

```
lab-credentials.md    current Qwiklabs username and password
```

Copy the example and fill it in at the start of each lab:

```bash
cp secrets/lab-credentials.md.example secrets/lab-credentials.md
```

Everything in here except `README.md` and `*.example` is gitignored.

The project ID is not a secret in the security sense, but it changes every lab,
so it lives in `terraform/lab.tfvars` instead of being duplicated here. That file
is gitignored too, and it is the only place the project ID appears.
