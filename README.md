
License: MIT

Attribution: e-centricity, LLP
https://github.com/e-centricity/word-histograms.git

Installation:
  download and call `bundle`

Usage:

$ bundle exec ruby word_histograms.rb --min-match-count 3 list_of_docs.txt keywords.yaml
+------------------+---------------------------------------------+------------------+
| category         | blocks (1000 min chars) which meet criteria | scale (relative) |
+------------------+---------------------------------------------+------------------+
| multimodal       | 11                                          | 1                |
| efficiency       | 19                                          | 2                |
| environment      | 52                                          | 5                |
| electric         | 88                                          | 8                |
| maintenance      | 110                                         | 10               |
| safety           | 121                                         | 11               |
| complete streets | 189                                         | 17               |
| congestion       | 258                                         | 23               |
| intelligent      | 283                                         | 26               |
| mobility         | 357                                         | 32               |
| land use         | 417                                         | 38               |
| walking          | 471                                         | 43               |
| connectivity     | 534                                         | 49               |
| public transit   | 993                                         | 90               |
+------------------+---------------------------------------------+------------------+
14 rows in set
+-----------------+-------+
| option          | value |
+-----------------+-------+
| block-size      | 1000  |
| min-match-count | 3     |
+-----------------+-------+
2 rows in set