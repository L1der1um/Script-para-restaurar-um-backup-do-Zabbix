# ♻️ Zabbix Auto Restore

<p align="center">

![Bash](https://img.shields.io/badge/Bash-Script-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-Compatible-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Debian](https://img.shields.io/badge/Debian-Supported-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-Supported-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Zabbix](https://img.shields.io/badge/Zabbix-7.0_LTS-D40000?style=for-the-badge)
![MySQL](https://img.shields.io/badge/MySQL-Restore-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

</p>

Script desenvolvido para realizar a **restauração completa de ambientes Zabbix 7.0 LTS**, recuperando automaticamente o banco de dados MySQL/MariaDB e os arquivos de configuração previamente armazenados em backups.

O processo foi projetado para ser **seguro, automatizado e interativo**, reduzindo o tempo necessário para recuperação de ambientes em casos de falha, migração ou desastre.

---

# 📦 Este projeto

Este script foi desenvolvido para restaurar ambientes **Zabbix 7.0 LTS** a partir de backups previamente gerados, automatizando a recuperação do banco de dados e dos arquivos de configuração.

Ele faz parte de uma suíte de automação para o Zabbix, composta por scripts de instalação, backup e restauração.

---

# ✨ Funcionalidades

- ♻️ Restauração completa do ambiente Zabbix.
- 📂 Menu interativo para seleção do backup.
- 🔍 Listagem automática dos backups disponíveis.
- 📦 Restauração dos arquivos físicos.
- 🛢️ Restauração automática do banco MySQL/MariaDB.
- 🔧 Conversão automática de collation entre versões do MySQL.
- 🛑 Interrupção automática dos serviços durante a restauração.
- 🔒 Gerenciamento automático do parâmetro `log_bin_trust_function_creators`.
- 🚀 Reinicialização automática dos serviços.
- 📋 Exibição de erros detalhados caso a restauração falhe.

---

# 📁 Estrutura esperada

Os backups devem estar armazenados em:

```text
/backup_zabbix
```

Exemplo:

```text
/backup_zabbix

├── bkp_2026-07-30
│   ├── zabbix_db_20260730.sql.gz
│   └── zabbix_dirs_20260730.tar.gz
│
├── bkp_2026-07-29
│   ├── zabbix_db_20260729.sql.gz
│   └── zabbix_dirs_20260729.tar.gz
│
└── bkp_2026-07-28
    ├── zabbix_db_20260728.sql.gz
    └── zabbix_dirs_20260728.tar.gz
```

---

# 📦 Arquivos esperados

Cada backup deve conter:

| Arquivo | Descrição |
|----------|-----------|
| `zabbix_db_*.sql.gz` | Dump compactado do banco de dados |
| `zabbix_dirs_*.tar.gz` | Backup dos arquivos do Zabbix |

Caso apenas o banco esteja presente, o script continuará normalmente e restaurará somente os dados.

---

# ⚙️ Como funciona

O processo de restauração é dividido em várias etapas para garantir a consistência do ambiente.

---

## 1️⃣ Seleção do backup

O script lista automaticamente todos os backups encontrados.

Exemplo:

```text
1. bkp_2026-07-30

2. bkp_2026-07-29

3. bkp_2026-07-28
```

Após selecionar o backup, seus arquivos são exibidos para conferência.

---

## 2️⃣ Coleta das credenciais

São solicitadas as credenciais do banco de dados:

- usuário MySQL;
- senha.

Essas informações são utilizadas para recriar o banco do Zabbix.

---

## 3️⃣ Parada dos serviços

São interrompidos automaticamente:

- Zabbix Server
- Zabbix Agent
- Apache

Isso evita gravações concorrentes durante a restauração.

---

## 4️⃣ Preparação do banco

O script:

- habilita temporariamente `log_bin_trust_function_creators`;
- remove o banco existente;
- cria um banco limpo;
- prepara o ambiente para importação.

---

## 5️⃣ Importação do banco

O dump SQL é restaurado automaticamente.

Durante esse processo o script realiza adaptações de compatibilidade entre versões do MySQL, incluindo ajustes automáticos de:

- charset;
- collation;
- utf8mb3;
- utf8mb4;
- InnoDB.

Essas conversões aumentam significativamente a compatibilidade entre diferentes versões do MySQL e MariaDB.

---

## 6️⃣ Restauração dos arquivos

Caso exista um arquivo:

```text
zabbix_dirs_*.tar.gz
```

ele será extraído automaticamente, restaurando:

- configurações;
- scripts;
- arquivos adicionais do ambiente.

Caso esse arquivo não exista, somente o banco de dados será restaurado.

---

## 7️⃣ Inicialização

Ao finalizar:

- o parâmetro de segurança do MySQL é restaurado;
- os serviços do Zabbix são iniciados novamente.

---

# 🔄 Fluxo da restauração

```text
Selecionar Backup
        │
        ▼
Solicitar Credenciais
        │
        ▼
Parar Serviços
        │
        ▼
Recriar Banco
        │
        ▼
Importar Banco
        │
        ▼
Restaurar Arquivos
        │
        ▼
Iniciar Serviços
        │
        ▼
Restauração Finalizada
```

---

# ▶️ Execução

Conceda permissão ao script:

```bash
chmod +x restore_zabbix7.sh
```

Execute como root:

```bash
sudo ./restore_zabbix7.sh
```

---

# 📋 Etapas exibidas

Durante a restauração são exibidas mensagens semelhantes a:

```text
Selecionando backup...

Parando serviços...

Recriando banco...

Importando banco...

Restaurando arquivos...

Reiniciando serviços...

Restauração concluída!
```

---

# 🔒 Segurança

Durante a restauração o script:

- interrompe todos os serviços do Zabbix;
- recria completamente o banco de dados;
- restaura automaticamente a configuração de segurança do MySQL;
- valida a importação antes de continuar.

Caso algum erro seja encontrado, a restauração é interrompida imediatamente para evitar inconsistências.

---

# 📌 Pré-requisitos

- Debian ou Ubuntu
- MySQL ou MariaDB instalado
- Permissão de root
- Backup previamente gerado
- Diretório `/backup_zabbix`

---

# 📊 Exemplo de saída

```text
Backup selecionado:

bkp_2026-07-30

Banco restaurado com sucesso.

Arquivos restaurados.

Serviços iniciados.

Restauração concluída!
```

---

# ✅ Benefícios

- Processo totalmente automatizado
- Compatível com MySQL e MariaDB
- Conversão automática entre versões
- Restauração rápida
- Interface simples e intuitiva
- Ideal para Disaster Recovery
- Recuperação completa do ambiente
- Compatível com os backups gerados pelo script **Zabbix Backup**

---

# 🛠️ Tecnologias utilizadas

- Bash
- MySQL
- MariaDB
- tar
- gzip
- sed
- systemd

---

# 📄 Licença

Este projeto está licenciado sob a licença **MIT**.

Você pode utilizar, modificar e distribuir este projeto livremente, desde que mantenha os créditos e o texto da licença.

---

# 👨‍💻 Autor

Desenvolvido para automatizar a restauração de ambientes **Zabbix 7.0 LTS**, reduzindo o tempo de recuperação, padronizando procedimentos de Disaster Recovery e simplificando a administração de servidores Linux.
```
