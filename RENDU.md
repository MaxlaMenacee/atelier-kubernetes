# Rendu — Atelier Kubernetes

> Complétez ce fichier au fil de l'atelier, puis faites un commit et un push (voir la section « Rendu » du README).

**Nom / Prénom :** BRUN Maxime
**Groupe :** RS2

> Toutes les sorties citées ci-dessous viennent de l'exécution réelle dans le Codespace (k3d v5.9.0, k3s v1.35.5). Les journaux complets (commandes et sorties) sont dans le dossier [`preuves/`](preuves/).

---

## Exercice 1 — Cluster

1. Combien de nœuds affiche `kubectl get nodes` ? Quel est le rôle de chacun ?
   > **3 nœuds**, tous `Ready` :
   > - `k3d-lab-server-0`, rôle `control-plane` : c'est le « master ». Il héberge l'API Server, le scheduler, le controller-manager et la base d'état du cluster (SQLite via kine dans k3s, etcd en général).
   > - `k3d-lab-agent-0` et `k3d-lab-agent-1`, rôle `<none>` : ce sont les workers. Leur kubelet et leur containerd exécutent les pods.
   >
   > Particularité de k3s : le server n'est pas « tainté », il accepte donc aussi des pods (on y retrouve `metrics-server` et des pods `site`).
2. Que montre `docker ps` ? Qu'est-ce qu'un « nœud » dans k3d, concrètement ?
   > `docker ps` montre **4 conteneurs** :
   > - 3 conteneurs `rancher/k3s:v1.35.5-k3s1` : `k3d-lab-server-0`, `k3d-lab-agent-0` et `k3d-lab-agent-1` ;
   > - `k3d-lab-serverlb` (`ghcr.io/k3d-io/k3d-proxy`), le load balancer qui publie `8081->80` (vers Traefik) et `38161->6443` (l'API Server joint par `kubectl`).
   >
   > Concrètement, un nœud k3d est donc **un conteneur Docker qui exécute k3s**, avec son propre containerd à l'intérieur : les pods sont des conteneurs dans un conteneur.
   >
   > Sur le cluster « vide », `kubectl get pods -A` montre déjà les composants système, tous dans le namespace **`kube-system`** : `coredns` (DNS interne), `traefik` (Ingress Controller) et ses `svclb-traefik` (un par nœud, DaemonSet), `metrics-server`, `local-path-provisioner` (volumes persistants), ainsi que les jobs `helm-install-traefik*` (`Completed`).

## Exercice 2 — Premier déploiement

3. Quels objets Kubernetes ont été créés par `kubectl create deployment` ? (indice : `kubectl get all`)
   > Une chaîne de trois objets : le **Deployment** `web`, qui a créé un **ReplicaSet** `web-68d995574f`, qui a créé un **Pod** `web-68d995574f-rmscl`. Le **Service** `web` (ClusterIP 10.43.55.209, port 80) vient de `kubectl expose`. Le Service `kubernetes` existait déjà.
4. Vous avez supprimé le pod `web-...` : que s'est-il passé, et pourquoi ?
   > Dans `kubectl get pods -w`, l'ancien pod `web-68d995574f-rmscl` passe en `Terminating`. Au même moment apparaît un **nouveau pod au nom différent**, `web-68d995574f-xmlxm` : `Pending`, puis `ContainerCreating`, puis `Running` en environ 5 s.
   >
   > Le ReplicaSet (`DESIRED 1`) constate que l'état réel (0 pod) ne correspond plus à l'état désiré (1 pod) et en recrée un : c'est la **boucle de réconciliation**. On ne gère pas des pods mais un état désiré.

## Exercice 3 — Modifier un conteneur en direct

5. Après suppression du pod, votre message « Bienvenue... » a-t-il survécu ? Pourquoi ?
   > **Non.** Avant la suppression, `curl` renvoyait `<h1>Bienvenue sur mon site Web</h1>`. Après la suppression et la relance du tunnel, on retrouve `<h1>Welcome to nginx!</h1>`.
   >
   > Le système de fichiers d'un conteneur est **éphémère** : la modification était écrite dans la couche du conteneur supprimé. Le nouveau pod repart de l'image `nginx` d'origine. Le contenu doit donc être décrit en dehors du conteneur (ConfigMap, volume, image).
6. Pourquoi le `port-forward` a-t-il cessé de fonctionner après la suppression du pod ?
   > `kubectl port-forward svc/web` ne passe pas réellement par le Service : il choisit **un pod** derrière le Service et ouvre un tunnel vers ce pod précis. Quand ce pod disparaît, le tunnel casse.
   >
   > `curl` renvoie `Empty reply from server`, et `/tmp/web.log` indique `error forwarding port 80 to pod ... network namespace for sandbox ... is closed`, puis `error: lost connection to pod`.

## Exercice 4 — Déclaratif

7. Quelle différence entre `kubectl create` et `kubectl apply` ?
   > - `kubectl create` est **impératif** : « crée cet objet ». Il échoue (`AlreadyExists`) si l'objet existe déjà et ne sait pas mettre à jour.
   > - `kubectl apply -f` est **déclaratif** : « voici l'état voulu ». Il crée ce qui manque, met à jour ce qui diffère (fusion à trois voies grâce à l'annotation `last-applied-configuration`) et ne touche pas au reste. Il est **idempotent** : relancé sans changement, il répond `unchanged`.
   >
   > Exemple vécu : après modification de la ConfigMap, `apply` a répondu `configmap/site-html configured`, `deployment.apps/site unchanged`, `service/site unchanged`. Les fichiers YAML versionnés dans Git deviennent la source de vérité.
8. À quoi sert le `selector` d'un Service ? Que se passe-t-il s'il ne correspond à aucun pod ?
   > Le `selector` (`app: site`) désigne, par leurs **labels**, les pods qui reçoivent le trafic du Service. Les pods prêts qui correspondent deviennent ses **endpoints** (`kubectl get endpoints site` → `10.42.1.6:80`).
   >
   > S'il ne correspond à aucun pod, le Service existe et garde son IP, mais il n'a **aucun endpoint**, donc les connexions échouent. Je l'ai vérifié avec un Service de test au selector `app=test-selector` : `kubectl get endpoints test-selector` → `<none>`.

## Exercice 5 — Scaling & mises à jour

9. Sur quels nœuds se trouvent vos 3 réplicas ? Collez la sortie de `kubectl get pods -l app=site -o wide`.
   ```
   NAME                   READY   STATUS    RESTARTS   AGE   IP          NODE               NOMINATED NODE   READINESS GATES
   site-75775484b-mn965   1/1     Running   0          6s    10.42.0.7   k3d-lab-agent-0    <none>           <none>
   site-75775484b-mqhgz   1/1     Running   0          6s    10.42.2.6   k3d-lab-server-0   <none>           <none>
   site-75775484b-zzgcc   1/1     Running   0          82s   10.42.1.6   k3d-lab-agent-1    <none>           <none>
   ```
   > Un réplica par nœud : le scheduler répartit les pods, y compris sur le control plane, schedulable dans k3s. Après la mise à jour vers `nginx:1.28`, les nouveaux pods se sont de nouveau répartis sur les 3 nœuds, remplacés un par un (rolling update : révisions 1 → 2).
10. Avec l'image `nginx:9.99`, quel statut avait le pod ? Quelle commande vous a donné la cause ?
    > Le nouveau pod `site-fc576997-vt77m` est resté `0/1`, en **`ErrImagePull`** puis **`ImagePullBackOff`**.
    >
    > La cause exacte vient de **`kubectl describe pod site-fc576997-vt77m`**, section *Events* : `Failed to pull image "nginx:9.99": ... docker.io/library/nginx:9.99: not found`. Le tag n'existe pas sur Docker Hub. On obtient le même message avec `kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[0].state.waiting}'`.
11. Pendant la panne, le site restait-il accessible ? Pourquoi ?
    > **Oui.** `curl` renvoyait toujours la page, et `kubectl get deploy site` affichait `READY 3/3`, `UP-TO-DATE 1`.
    >
    > Avec la stratégie RollingUpdate par défaut (`maxSurge 25%` → 1 pod en plus, `maxUnavailable 25%` → 0 pod en moins pour 3 réplicas), Kubernetes crée d'abord le nouveau pod et ne supprime un ancien que lorsque le nouveau est prêt. Le pod 9.99 n'étant jamais prêt, les 3 anciens pods sont restés en service. Le Service n'envoie le trafic qu'aux pods prêts (`10.42.0.8`, `10.42.1.7`, `10.42.2.7`).
    >
    > Ensuite, `kubectl rollout undo` a ramené `nginx:1.28` (révision 4), et `kubectl diff -f k8s/site/` ne montre plus aucun écart : le cluster correspond de nouveau aux fichiers du dépôt.

## Exercice 6 — Portainer & Mario

12. URL publique de votre Mario :
    > https://ideal-capybara-r4grv5v67qrw35pjv-8585.app.github.dev/
    >
    > Port 8585 passé en visibilité `public`. Un accès sans authentification GitHub répond `HTTP 200` avec la page « Super Mario Bros in HTML5 ». L'URL ne fonctionne que tant que le Codespace et le `port-forward` tournent.
13. Retrouvez le Deployment `mario` en ligne de commande. Portainer et `kubectl` parlent-ils au même composant ? Lequel ?
    > **Oui, au même composant : l'API Server (kube-apiserver) du control plane.**
    > - `kubectl` le joint par le kubeconfig, via le load balancer k3d (`https://0.0.0.0:38161` → port 6443 de `k3d-lab-server-0`).
    > - Portainer tourne dans le cluster et le joint par l'adresse interne `https://kubernetes.default.svc` (URL de l'environnement `local`). Il s'authentifie avec son ServiceAccount `portainer-sa-clusteradmin`, lié au rôle cluster-admin.
    >
    > C'est pourquoi le Deployment créé dans Portainer apparaît aussitôt dans `kubectl get deploy mario`. Il est identique sur le fond (même `selector` `app: mario`, même template), mais Portainer y ajoute ses propres labels de suivi : `io.portainer.kubernetes.application.stack=mario`, `...owner=admin`, `...stackid=1`, `...kind=content`. Le Deployment `web` créé par `kubectl create` ne porte que `app=web`.
    >
    > Remarque : depuis Portainer 2.45, la création du compte admin exige un **jeton d'installation** affiché dans les logs du pod (`kubectl logs -n portainer deploy/portainer`, en-tête `X-Setup-Token`). Sans lui, l'appel est refusé (HTTP 403). Le compte admin et le déploiement de Mario (stack Kubernetes `mario` du namespace `default`, comme *Create from manifest*) ont été faits avec l'API de Portainer, dans le terminal.

## Bonus (facultatif)

14. Bonus réalisés et remarques :
    > **A — Ingress** : Ingress `site` (classe `traefik`) vers le Service `site:80`, joignable sur le port 8081. J'ai supprimé les 3 pods un par un tout en envoyant une requête par seconde : **40 requêtes sur 40 ont réussi**. Contrairement au `port-forward`, l'Ingress suit les endpoints du Service.
    >
    > **B — Probes et ressources** : `readinessProbe` HTTP sur `/:80`, `requests` 50m CPU / 32Mi et `limits` 100m / 64Mi. Avec une probe sur `/nope` (Deployment de test séparé), le pod reste `Running` mais `0/1` : *Readiness probe failed: HTTP probe failed with statuscode: 404*. Il ne reçoit donc jamais de trafic, et un rolling update vers une telle version resterait bloqué sans couper le service.
    >
    > **C — Drain** : `kubectl drain k3d-lab-agent-0` passe le nœud en `SchedulingDisabled` et évince ses pods. Le pod `site` est recréé ailleurs (sur `server-0`). Portainer reste `Pending`, car son volume `local-path` est lié au disque de `agent-0`. Après `uncordon`, Portainer y redémarre, mais **les pods `site` ne reviennent pas** : le scheduler ne place que les nouveaux pods et ne rééquilibre jamais ceux qui tournent déjà.
    >
    > **D — Namespaces** : namespace `prod` avec une seconde copie complète du site (Deployment, Service, ConfigMap du même nom, 3 réplicas), sans conflit avec `default`. Les noms sont isolés par namespace, et Portainer liste bien `prod` séparément de `default`.

---

**Score obtenu avec `./scripts/check.sh` :** 18 / 18
