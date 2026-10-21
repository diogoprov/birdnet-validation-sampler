# Rode a partir da raiz do repositorio: source("data-raw/hex/make_hex.R")
# Hex sticker do sheepdog, na mesma linha do crywolf (paleta 80s, fonte
# Righteous; ver crywolf/dev/hex/make_hex_80s_v2.R), com a moldura ciano
# como par do crywolf magenta: o cao escuta o chamado que o lobo emite.
# Silhueta: Canis lupus familiaris by Mozillian, PhyloPic, CC0 1.0
# https://www.phylopic.org/images/d3e8133c-e669-4881-9111-b44145f94212
library(hexSticker); library(ggplot2); library(showtext)
sysfonts::font_add_google("Righteous", "righteous")
showtext_auto()

bg <- "#241042"; magenta <- "#FF3EA5"; cyan <- "#2DE2E6"; sun1 <- "#FFB627"
cream <- "#F4EBD9"

# silhueta em creme (o svg original e preto)
svg <- readLines("data-raw/hex/pp/dog_sitting.svg")
svg <- gsub('fill="#000000"', paste0('fill="', cream, '"'), svg, fixed = TRUE)
tmp <- tempfile(fileext = ".svg")
writeLines(svg, tmp)
dog_png <- rsvg::rsvg(tmp, width = 1536)
dog_box <- c(xmin = 0.4, xmax = 8.4, ymin = -0.75,
             ymax = -0.75 + 8.0 * dim(dog_png)[1] / dim(dog_png)[2])

circ <- function(cx, cy, r, n = 200, from = 0, to = 360) {
  th <- seq(from, to, length.out = n) * pi / 180
  data.frame(x = cx + r * cos(th), y = cy + r * sin(th))
}
sun <- circ(6.6, 7.6, 3.1)
bands <- data.frame(ymin = c(4.9, 5.65, 6.3, 6.85), ymax = c(5.3, 5.95, 6.5, 6.95))
arcs <- do.call(rbind, lapply(c(0.8, 1.45, 2.1), function(r)
  transform(circ(11.9, 7.4, r, 60, 145, 215), r = r)))
set.seed(7)
eq <- data.frame(x = seq(0.4, 10.2, by = 0.5))
eq$h <- 0.25 + 0.9 * abs(sin(eq$x * 1.3)) * runif(nrow(eq), 0.5, 1)
# barras magenta: deteccoes rejeitadas na validacao
eq$cor <- ifelse(seq_len(nrow(eq)) %in% c(6, 13), magenta, cyan)

p <- ggplot() +
  geom_polygon(data = sun, aes(x, y), fill = sun1, colour = NA) +
  geom_rect(data = bands, aes(xmin = 3.2, xmax = 10.0, ymin = ymin, ymax = ymax),
            fill = bg, colour = NA) +
  geom_rect(data = eq, aes(xmin = x - 0.17, xmax = x + 0.17,
                           ymin = -1.0, ymax = -1.0 + h, fill = I(cor))) +
  geom_path(data = arcs, aes(x, y, group = r), colour = cyan,
            linewidth = 1.3, lineend = "round") +
  annotation_raster(dog_png, dog_box["xmin"], dog_box["xmax"],
                    dog_box["ymin"], dog_box["ymax"], interpolate = TRUE) +
  coord_fixed(xlim = c(-2.0, 11.0), ylim = c(-1.6, 11.4), expand = FALSE) +
  theme_void() + theme_transparent()

make <- function(file, size, dpi = NULL) {
  if (!is.null(dpi)) showtext_opts(dpi = dpi)
  args <- list(p, package = "sheepdog",
               p_family = "righteous", p_size = size, p_color = cream,
               p_x = 1, p_y = 0.42,
               s_x = 1.0, s_y = 1.15, s_width = 1.15, s_height = 1.15,
               h_fill = bg, h_color = cyan, h_size = 1.6,
               filename = file)
  if (!is.null(dpi)) args$dpi <- dpi
  do.call(sticker, args)
}
make("man/figures/logo.png", 5.7, dpi = 600)
make("man/figures/logo.svg", 5.7 * 96 / 600 * 5.4, dpi = 96)
