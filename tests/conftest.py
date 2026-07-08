"""
Configuração compartilhada dos testes.

Resolve a colisão de nomes: há dois arquivos handler.py (ingestão e consumer) e um producer.py. 
Importá-los como `import handler` causaria conflito de namespace.

`load_module` carrega cada arquivo pelo CAMINHO ABSOLUTO, com um nome de
módulo único, eliminando a colisão. Assim `pytest tests/` roda tudo de uma vez
sem depender da ordem do PYTHONPATH.
"""
import importlib.util
import sys
from pathlib import Path

# raiz do projeto (um nível acima de tests/)
ROOT = Path(__file__).resolve().parent.parent


def load_module(nome_unico: str, caminho_relativo: str):
    """
    Carrega um módulo Python pelo caminho do arquivo, com nome único.

    Ex: load_module("ingestion_handler", "src/ingestion/coingecko/handler.py")
    Recarrega a cada chamada (importlib) para respeitar env vars setadas no teste.
    """
    caminho = ROOT / caminho_relativo
    spec = importlib.util.spec_from_file_location(nome_unico, caminho)
    modulo = importlib.util.module_from_spec(spec)
    sys.modules[nome_unico] = modulo
    spec.loader.exec_module(modulo)
    return modulo
