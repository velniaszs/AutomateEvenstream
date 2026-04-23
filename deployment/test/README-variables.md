# 2. Create and activate venv
cd C:\GIT\GIT\AutomateEvenstream\deployment
py -3.12 -m venv venv-py312
.\venv-py312\Scripts\Activate.ps1

# 3. Install packages
pip install fabric-cicd azure-identity requests pyyaml semantic-link-labs

# 4. Run deployment
python deploy-local.py --environment TEST