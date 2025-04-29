"""Utility used to convert PNG map into a text file readable by the simulation setup."""

from PIL import Image

def convert_image_to_ascii(image_path, output_path):
    """
    Converts a PNG image with specific colors to ASCII map and saves it to a file.

    Args:
        image_path (str): Path to the input PNG image file.
        output_path (str): Path to the output text file.
    """
    color_map = {
        (255, 0, 0): 'D',    # ff0000 - Red
        (155, 208, 138): 'S', # 9bd08a - Greenish
        (255, 255, 255): 'C', # ffffff - White
        (97, 68, 44): 'B',   # 61442c - Brown
        (141, 141, 141): 'R'  # 8c8c8c - Gray 8d8d8d
    }
    default_char = 'S'
    ascii_art = []

    try:
        # Ensure image is in RGB format
        img = Image.open(image_path).convert('RGB')
        width, height = img.size

        for y in range(height):
            row = ""
            for x in range(width):
                r, g, b = img.getpixel((x, y))
                # Find the closest match or default
                char = color_map.get((r, g, b), default_char)
                row += char
            ascii_art.append(row)

        with open(output_path, 'w') as f:
            f.write('\n'.join(ascii_art))

        print(f"Successfully converted '{image_path}' to ASCII art in '{output_path}'")

    except FileNotFoundError:
        print(f"Error: Image file not found at '{image_path}'")
    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == "__main__":
    input_image = "map.png"
    output_file = "map.txt"
    convert_image_to_ascii(input_image, output_file)