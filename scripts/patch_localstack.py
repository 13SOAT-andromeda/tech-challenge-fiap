"""
Patch LocalStack's pull_image method to use the local Docker cache instead of
always contacting the remote registry. Required because Docker Desktop's daemon
cannot reach localhost.localstack.cloud:4510 (LocalStack's ECR) from the Windows VM.

Safe to run multiple times — checks if already applied.
"""

filepath = '/opt/code/localstack/.venv/lib/python3.13/site-packages/localstack/utils/container_utils/docker_sdk_client.py'

with open(filepath, 'r') as f:
    content = f.read()

if 'found in local cache, skipping remote pull' in content:
    print("Patch already applied — skipping.")
    exit(0)

old_block = '''        try:
            if log_handler:
                # Use a lower-level API, as the 'stream' argument is not available in the higher-level `pull`-API
                kwargs["stream"] = True
                stream = self.client().api.pull(docker_image, **kwargs)
                for line in stream:
                    log_handler(to_str(line))
            else:
                self.client().images.pull(docker_image, **kwargs)
        except ImageNotFound:
            raise NoSuchImage(docker_image)
        except APIError as e:
            message = "APIError in Docker process"
            if e.status_code:
                message = f"{message} returned with status_code {e.status_code}"
            raise ContainerException(message, stdout=str(e)) from e

    def push_image'''

new_block = '''        try:
            # Use local cache if image already exists to avoid registry connectivity issues
            try:
                self.client().images.get(docker_image)
                LOG.debug("Image %s found in local cache, skipping remote pull", docker_image)
                return
            except Exception:
                pass
            if log_handler:
                # Use a lower-level API, as the 'stream' argument is not available in the higher-level `pull`-API
                kwargs["stream"] = True
                stream = self.client().api.pull(docker_image, **kwargs)
                for line in stream:
                    log_handler(to_str(line))
            else:
                self.client().images.pull(docker_image, **kwargs)
        except ImageNotFound:
            raise NoSuchImage(docker_image)
        except APIError as e:
            message = "APIError in Docker process"
            if e.status_code:
                message = f"{message} returned with status_code {e.status_code}"
            raise ContainerException(message, stdout=str(e)) from e

    def push_image'''

if old_block not in content:
    print("ERROR: Pattern not found — LocalStack version may have changed.")
    exit(1)

with open(filepath, 'w') as f:
    f.write(content.replace(old_block, new_block, 1))

print("Patch applied successfully.")
