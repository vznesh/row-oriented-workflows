#' ---
#' title: "Row-wise Summaries"
#' author: "Jenny Bryan"
#' date: "`r format(Sys.Date())`"
#' output: github_document
#' ---

#+ setup, include = FALSE, cache = FALSE
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  error = TRUE
)
options(tidyverse.quiet = TRUE)

#' > For rowSums, mtcars %>% mutate(rowsum = pmap_dbl(., sum)) works but is
#' > a tidy oneliner for mean or sd per row?
#' > I'm looking for a tidy version of rowSums, rowMeans and similarly rowSDs...
#'
#' [Two](https://twitter.com/vrnijs/status/995129678284255233)
#' [tweets](https://twitter.com/vrnijs/status/995193240864178177) from Vincent
#' Nijs [github](https://github.com/vnijs),
#' [twitter](https://twitter.com/vrnijs)
#'

#' Good question! This also came up when I was originally casting about for
#' genuine row-wise operations, but I never worked it up. I will do so now!
#' First I set up my example.
#'
#+ body
# ----
library(tidyverse)

df <- tribble(
  ~ name, ~ t1, ~t2, ~t3,
  "Abby",    1,   2,   3,
  "Bess",    4,   5,   6,
  "Carl",    7,   8,   9
)

#' ## Use `rowSums()` and `rowMeans()` inside `dplyr::mutate()`
#'
#' One "tidy version" of `rowSums()` is to ... just stick `rowSums()` inside a
#' tidyverse pipeline. You can use `rowSums()` and `rowMeans()` inside
#' `mutate()`, because they have a method for `data.frame`:
df %>%
  mutate(t_sum = rowSums(select_if(., is.numeric)))

df %>%
  mutate(t_avg = rowMeans(select(., -name)))

#' Above I also demonstrate the use of `select(., SOME_EXPRESSION)` to express
#' which variables should be computed on.  This comes up a lot in row-wise work
#' with a data frame, because, almost by definition, your variables are of mixed
#' type. These are just a few examples of the different ways to say "use `t1`,
#' `t2`, and `t3`", so we don't try to sum or average `name`. I'll continue to
#' mix these in as we go. They are equally useful when expressing which
#' variables should be forwarded to `.f` inside `pmap_*().`
#'
#' ## Devil's Advocate: can't you just use `rowMeans()` and `rowSums()` alone?
#'
#' This is a great point [raised by Diogo
#' Camacho](https://twitter.com/DiogoMCamacho/status/996178967647412224). If
#' `rowSums()` and `rowMeans()` get the job done, why put yourself through the
#' pain of using `pmap()`, especially inside `mutate()`?
#'
#' There are a few reasons:
#'
#' * You might want to take the median or standard deviation instead of a mean
#' or a sum. You can't assume that base R or an add-on package offers a row-wise
#' `data.frame` method for every function you might need.
#' * You might have several variables besides `name` that need to be retained,
#' but that should not be forwarded to `rowSums()` or `rowMeans()`. A
#' matrix-with-row-names grants you a reprieve for exactly one variable and that
#' variable best not be integer, factor, date, or datetime. Because you must
#' store it as character. It's not a general solution.
#' * Correctness. If you extract the numeric columns or the variables whose
#' names start with `"t"`, compute `rowMeans()` on them, and then column-bind
#' the result back to the data, you are responsible for making sure that the two
#' objects are absolutely, positively row-aligned.
#'
#' I think it's important to have a general strategy for row-wise computation on
#' a subset of the columns in a data frame.
#'
#' ## How to use an arbitrary function inside `pmap()`
#'
#' What if you need to apply `foo()` to rows and the universe has not provided a
#' special-purpose `rowFoos()` function? Now you do need to use `pmap()` or a
#' type-stable variant, with `foo()` playing the role of `.f`.
#'
#' This works especially well with `sum()`.

df %>%
  mutate(t_sum = pmap_dbl(list(t1, t2, t3), sum))

df %>%
  mutate(t_sum = pmap_dbl(select(., starts_with("t")), sum))

#' But the original question was about means and standard deviations! Why is
#' that any different? Look at the signature of `sum()` versus a few other
#' numerical summaries:
#'
#+ eval = FALSE
   sum(..., na.rm = FALSE)
  mean(x, trim = 0, na.rm = FALSE, ...)
median(x, na.rm = FALSE, ...)
   var(x, y = NULL, na.rm = FALSE, use)

#' `sum()` is especially `pmap()`-friendly because it takes `...` as its primary
#' argument. In contrast, `mean()` takes a vector `x` as primary argument, which
#' makes it harder to just drop into `pmap()`. This is something you might never
#' think about if you're used to using special-purpose helpers like
#' `rowMeans()`.
#'
#' purrr has a family of `lift_*()` functions that help you convert between
#' these forms. Here I apply `purrr::lift_vd()` to `mean()`, so I can use it
#' inside `pmap()`. The "vd" says I want to convert a function that takes a
#' "**v**ector" into one that takes "**d**ots".
df %>%
  mutate(t_avg = pmap_dbl(list(t1, t2, t3), lift_vd(mean)))

#' ## Strategies that use reshaping and joins
#'
#' Data frames simply aren't a convenient storage format if you have a frequent
#' need to compute summaries, row-wise, on a subset of columns. It is highly
#' suggestive that your data is in the wrong shape, i.e. it's not tidy. Here we
#' explore some approaches that rely on reshaping and/or joining. They are more
#' transparent than using `lift_*()` with `pmap()` inside `mutate()` and,
#' consequently, more verbose.
#'
#' They all rely on forming row-wise summaries, then joining back to the data.
#'
#' ### Gather, group, summarize
(s <- df %>%
    gather("time", "val", starts_with("t")) %>%
    group_by(name) %>%
    summarize(t_avg = mean(val), t_sum = sum(val)))
df %>%
  left_join(s)

#' ### Group then summarise, with explicit `c()`
(s <- df %>%
    group_by(name) %>%
    summarise(t_avg = mean(c(t1, t2, t3))))
df %>%
  left_join(s)

#' ### Nesting
#'
#' Let's revisit a pattern from
#' [`ex08_nesting-is-good`](ex08_nesting-is-good.md). This is another way to
#' "package" up the values of `t1`, `t2`, and `t3` in a way that make both
#' `mean()` and `sum()` happy. *thanks @krlmlr*
(s <- df %>%
    gather("key", "value", -name) %>%
    nest(-name) %>%
    mutate(
      sum = map(data, "value") %>% map_dbl(sum),
      mean = map(data, "value") %>% map_dbl(mean)
    ) %>%
    select(-data))
df %>%
  left_join(s)

#' ### Yet another way to use `rowMeans()`
(s <- df %>%
    column_to_rownames("name") %>%
    rowMeans() %>%
    enframe())
df %>%
  left_join(s)

#' ## Maybe you should use a matrix
#'
#' If you truly have data where each row is:
#'
#'   * Identifier for this observational unit
#'   * Homogeneous vector of length n for the unit
#'
#' then you do want to use a matrix with rownames. I used to do this alot but
#' found that practically none of my data analysis problems live in this simple
#' world for more than a couple of hours. Eventually I always get back to a
#' setting where a data frame is the most favorable receptacle, overall. YMMV.
m <- matrix(
  1:9,
  byrow = TRUE, nrow = 3,
  dimnames = list(c("Abby", "Bess", "Carl"), paste0("t", 1:3))
)

cbind(m, rowsum = rowSums(m))
cbind(m, rowmean = rowMeans(m))
