Dans mon précédent homelab, j'avais 3 nodes en HA avec CEPH, de la redondance de services et tout le tralala. 3 fois plus de matériel veut dire 3 fois plus de pannes. J'utilise des mini PC qui ne sont pas prévus pour cet usage et de ce fait, deux ont déjà cramé (mais grâce à la garantie all good). J'ai pour objectif de faire quelque chose de moins ambitieux sans HA. Avant j'avais 3x64G de RAM, là j'aimerai passer à 1x128G.

Aussi, je suis en train de passer mon CCNA, et je me rends compte que mon archi network est nulle. Donc on va faire quelque chose de plus segmenté / sécurisé.

Freebox > OPNsense > VLANs

Je vais d'abord faire les updates de mon homelab, éteindre un node (l'archi fonctionne même avec 2 nodes disponibles) et le réinitialiser puis y installer Proxmox. La première VM à pop, c'est la VM OPNsense qui sera mon routeur. Une interface WAN en 192.168.0.253/24 avec comme gateway l'interface WAN de ma Freebox : 192.168.0.254/24. Ensuite on va commencer par un seul VLAN
