# Recipe Notes

This recipe was challenging to get working: the main issue was that the low bitrate encourages
GLM 5.3 flash to loop. Any time this recipe is updated, the responsible person should test
long agentic harness runs to ensure the model completes the tasks and does not fall into
catastrophic thinking or generation loops.

int4 does not seem to affect looping: the model also will loop in fp8. Run a comparison with
the full bf16 weights if you need to diagnose further.
