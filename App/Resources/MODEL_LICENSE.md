# PoseClassifier model licence

`PoseClassifier.mlpackage` was trained by EasyControl on hand landmarks extracted (with Apple Vision) from a
subset of **HaGRID — HAnd Gesture Recognition Image Dataset** by Alexander Kapitanov, Andrey Makhlyarchuk et al.
(https://github.com/hukenovs/hagrid), which is published under a public licence based on
Creative Commons Attribution-ShareAlike 4.0 (https://github.com/hukenovs/hagrid/blob/master/license/en_us.pdf).

Changes made to the licensed material: a subset of ~22 k images was selected by subject split; HaGRID's 34
gesture labels were remapped into EasyControl's classes (several merged into `none`); hand landmarks were re-detected with
Apple Vision and converted into 55-value feature vectors (with chirality-flipped copies for training); a new
classifier was trained on those vectors. No images are redistributed.

**Personal data:** the bundled model was additionally trained on hand-landmark recordings of the project's author
(recorded by the author for training; this is also the only source of the `pinch` class), so it is biased toward
that person's hand. No images or video are included — only 21-point hand landmarks were used. For distribution, a
HaGRID-only base model with on-device personalization is the intended path.

The model is licensed under **CC BY-SA 4.0** (https://creativecommons.org/licenses/by-sa/4.0/). It is provided
"as is", without warranties. The EasyControl source code is licensed separately.
