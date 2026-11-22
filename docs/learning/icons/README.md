# Icons for zero-drift-explorer.html

Downloaded 20/11/2026, unmodified. The page is built from
`../zero-drift-explorer.data.json` by the `project-explorer` skill, which embeds
only the icons used (base64), so the HTML works offline as one file. Rebuild
after editing the data or adding an icon:

```bash
python ~/.claude/skills/project-explorer/scripts/build.py   docs/learning/zero-drift-explorer.data.json docs/learning/zero-drift-explorer.html
```

| Files | Source | Licence / terms |
|---|---|---|
| `git.svg` | git-scm.com/downloads/logos (Git-Icon-1788C) | CC BY 3.0, Jason Long; unmodified |
| `github.svg`, `person.svg` | github.com/primer/octicons (mark-github-24, person-24) | MIT; fill colour added |
| `github-actions.svg`, `terraform.svg` | github.com/simple-icons/simple-icons | CC0 file; marks are trademarks of GitHub / HashiCorp; brand fill colour added |
| `k8s-*.svg` | github.com/kubernetes/community, `icons/svg/` | Apache-2.0 or CC-BY-4.0 (Kubernetes Icons Set, see its README) |
| `cncf-argo.svg`, `cncf-crossplane.svg`, `cncf-keda.svg`, `cncf-prometheus.svg` | github.com/cncf/artwork, `projects/<name>/icon/color/` | Linux Foundation trademark usage policy (cncf/artwork LICENSE.md) |
| `karpenter.svg` | github.com/aws/karpenter-provider-aws, `website/assets/icons/logo.svg` | Repository Apache-2.0; name and logo are trademarks of their owner |
| `aws-*.svg` | AWS Architecture Icons package 07/31/2026 (aws.amazon.com/architecture/icons) | AWS terms for using the icons in architecture diagrams |

No official logo was found for kro (kubernetes-sigs/kro has none in its
repository), Terraform, Kyverno admission, PostgreSQL or the RAG app, so the
page keeps emoji for those. Logos are used only to identify each tool in a
private study page; they do not imply endorsement.
