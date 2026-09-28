# AWS Lambda in 60 Minutes Companion Code

This repository contains the small Python Lambda function, local tests, sample events, and AWS CLI helper scripts used in *AWS Lambda in 60 Minutes* by Mason Ye.

The lab is intentionally small. It uses one Lambda function, one basic execution role, and one CloudWatch log group. It does not create a VPC, NAT Gateway, provisioned concurrency, EFS mount, API endpoint, or sustained workload.

## Prerequisites

- Python 3.11 or newer for local tests
- `zip`
- AWS CLI v2 for the optional cloud path
- AWS credentials with permission to manage the named Lambda function, its execution role, and its log group
- Region `ap-southeast-2`, or an explicit `AWS_REGION` override

## Run the local tests

```bash
./scripts/test.sh
```

## Build the deployment package

```bash
./scripts/package.sh
```

The package is written to `build/function.zip`.

## Deploy the bounded lab

Review the scripts before running them. The defaults create a function named `lambda-60-lab` and a role named `lambda-60-lab-role`.

```bash
./scripts/deploy.sh
```

Invoke the successful event:

```bash
./scripts/invoke.sh events/hello.json
```

Invoke the validation path:

```bash
./scripts/invoke.sh events/missing-name.json
```

The `intentional-failure.json` event deliberately raises an exception for the troubleshooting exercise.

## Clean up

Run cleanup even if you stop the lab early:

```bash
./scripts/cleanup.sh
```

Then verify in the AWS console that the function, log group, and lab role are gone. The project cost target is below US$1 and the hard ceiling is US$3, but actual charges depend on the account and region.

## Repository layout

```text
events/          Sample invocation payloads
infra/           Lambda execution-role trust policy
scripts/         Test, package, deploy, invoke, and cleanup helpers
src/             Lambda handler
tests/           Local unit tests
```

## Security notes

- Do not commit AWS credentials, account identifiers, request identifiers, signed URLs, or private data.
- Use a dedicated non-production AWS account or sandbox when possible.
- The sample execution role receives only the AWS managed basic Lambda logging policy.
- Review all commands before running them in an account you do not own.

## License

The companion code is provided under the MIT License. See `LICENSE-CODE.txt`.

