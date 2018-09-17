FROM dynverse/dynwrap:bioc

LABEL version 0.1.2

RUN R -e 'devtools::install_cran("monocle")'

ADD . /code

ENTRYPOINT Rscript /code/run.R
