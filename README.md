# Solutions Damn Vulnerable DeFi v4

TD Sécurité - Cours Monnaies Numériques 2026  
Par Sacha (zag2110)

## Description

Repo de mes solutions pour les challenges Damn Vulnerable DeFi. C'est un CTF de sécurité smart contracts avec 18 challenges qui couvrent pas mal de vulnérabilités classiques en DeFi (flash loans, réentrance, manipulation d'oracles, etc).

Le but c'est d'exploiter les failles dans les contrats pour récupérer/drainer des fonds ou compromettre le système. Tout est fait avec Foundry.

**Progression actuelle : 13/18 (72%)**

## Challenges résolus

| Challenge | Vulnérabilité exploitée | Notes |
|-----------|------------------------|-------|
| Unstoppable | DOS par déséquilibre du vault | Facile - juste envoyer des tokens direct |
| Naive Receiver | Multicall abuse | Utiliser multicall pour vider le receiver |
| Truster | Flash loan + approve() | Approuver puis transférer pendant le flash loan |
| Side Entrance | Réentrance classique | Deposit pendant le withdraw |
| The Rewarder | Flash loan + snapshot timing | Emprunter avant le snapshot |
| Selfie | Gouvernance takeover | Snapshot du voting power avec flash loan |
| Compromised | Oracle manipulation + crypto leak | Décoder les clés depuis base64 dans les logs |
| Puppet | Manipulation prix Uniswap V1 | Dump massif pour changer le prix spot |
| Puppet V2 | Pareil mais V2 | Même principe avec WETH/DVT pool |
| Free Rider | Bug dans le marketplace | Acheter tous les NFTs avec l'ETH d'un seul |
| Backdoor | Safe wallet + delegatecall | Exploit via le callback à l'init du wallet |
| Climber | Timelock bypass | Exploiter l'ordre execute() avant schedule() |
| Wallet Mining | CREATE2 salt mining | Bruteforce le salt pour avoir la bonne adresse |

## Challenges restants

Encore 5 à faire :
- ABI Smuggling (manipulation encodage bas niveau)
- Withdrawal (bridge L1/L2)
- Puppet V3 (Uniswap V3 oracle)
- Curvy Puppet (Curve oracle)
- Shards (NFT marketplace)

## Installation & Usage

```bash
git clone https://github.com/zag2110/TD-Security.git
cd TD-Security

# Config
cp .env.sample .env
# Mettre votre URL RPC Alchemy dans .env

forge build
forge install

# Lancer un test
forge test --match-test test_unstoppable -vv

# Avec plus de détails
forge test --match-test test_puppet -vvvv
```

## Notes techniques

**Framework** : Foundry (forge/cast/anvil)

**Techniques utilisées** :
- Flash loans pour les attaques one-shot
- vm.warp / vm.prank pour les cheatcodes 
- Forking mainnet quand nécessaire
- Création de contrats attaquants custom
- Exploitation de réentrance
- Manipulation d'oracles DEX
- Mining d'adresses avec CREATE2

**Méthodologie** :
1. Lire le code des contrats vulnérables
2. Identifier les invariants qui peuvent être cassés
3. Coder l'exploit dans le fichier de test
4. Valider que ça passe avec forge test

## Remarques

Tous les contrats ici sont VOLONTAIREMENT vulnérables. C'est pour apprendre.

**NE PAS utiliser ce code en prod évidemment.**

---

Projet basé sur [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) par The Red Guild  
Cours Sécurité & Monnaies Numériques - 2026
4. Tester avec `forge test --mp test/<nom-challenge>/<NomChallenge>.t.sol`

> Pour les challenges qui limitent le nombre de transactions, utiliser le flag `--isolate`.

### Mes Règles de Travail

- Toujours utiliser le compte `player`
- Ne pas modifier les conditions initiales ni finales
- Possibilité de déployer mes propres smart contracts
- Utiliser les cheatcodes Foundry pour avancer le temps si nécessaire

## Notes

Projet éducatif pour le cours Monnaies Numériques - Security
Tous les contrats sont intentionnellement vulnérables.

**⚠️ NE PAS UTILISER EN PRODUCTION ⚠️**

---

## Crédits

Projet original : [Damn Vulnerable DeFi](https://github.com/theredguild/damn-vulnerable-defi) par The Red Guild
Adapté par Sacha pour usage personnel et éducatif
