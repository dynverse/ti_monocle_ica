FROM dynverse/dynwrapr:v0.1.0

ARG GITHUB_PAT

RUN R -e 'devtools::install_cran("monocle")'

COPY definition.yml run.R example.h5 /code/

ENTRYPOINT ["/code/run.R"]
