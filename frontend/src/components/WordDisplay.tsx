import { Show, For } from 'solid-js';

interface WordDisplayProps {
    word?: string;
    wordOutline?: string[];
}

interface WordSegment {
    chars: string[];
    length: number;
    showLength: boolean;
}

function WordDisplay(props: WordDisplayProps) {
    const word = () => props.word || '';
    const wordOutline = () => props.wordOutline || [];

    // Group word outline into segments separated by non-alphabetic characters
    const wordSegments = (): WordSegment[] => {
        const outline = wordOutline();
        if (outline.length === 0) return [];

        const segments: WordSegment[] = [];
        let currentSegment: string[] = [];

        for (let i = 0; i < outline.length; i++) {
            const char = outline[i];
            const isAlphabetic =
                char === '' ||
                (char >= 'A' && char <= 'Z') ||
                (char >= 'a' && char <= 'z');

            if (!isAlphabetic) {
                // End current alphabetic segment if it exists
                if (currentSegment.length > 0) {
                    segments.push({
                        chars: currentSegment,
                        length: currentSegment.length,
                        showLength: true,
                    });
                    currentSegment = [];
                }

                // Add the non-alphabetic character as its own segment
                segments.push({
                    chars: [char],
                    length: 1,
                    showLength: false,
                });
            } else {
                currentSegment.push(char);
            }
        }

        // Add the last segment if it exists
        if (currentSegment.length > 0) {
            segments.push({
                chars: currentSegment,
                length: currentSegment.length,
                showLength: true,
            });
        }

        return segments;
    };

    return (
        <div class="font-retro flex-1 text-5xl text-amber-400 translate-y-0.75">
            <Show
                when={word()}
                fallback={
                    <Show
                        when={wordSegments().length > 0}
                        fallback={<span class="text-gray-400">&nbsp;</span>}
                    >
                        <div class="flex items-center gap-1 pb-5">
                            <For each={wordSegments()}>
                                {(segment) => (
                                    <div class="flex flex-col items-center gap-1">
                                        <div class="flex gap-1">
                                            <For each={segment.chars}>
                                                {(char) => (
                                                    <span class="inline-block min-w-[1rem] text-center">
                                                        {char ? (
                                                            char
                                                        ) : (
                                                            <span class="relative top-4 inline-block w-4 border-b-4 border-gray-800"></span>
                                                        )}
                                                    </span>
                                                )}
                                            </For>
                                        </div>
                                        <Show when={segment.showLength}>
                                            <span class="relative top-2 text-sm text-gray-600">
                                                ({segment.length})
                                            </span>
                                        </Show>
                                    </div>
                                )}
                            </For>
                        </div>
                    </Show>
                }
            >
                <span>{word()}</span>
            </Show>
        </div>
    );
}

export default WordDisplay;
